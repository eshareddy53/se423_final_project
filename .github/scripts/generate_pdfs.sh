#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e 

# Default to "workspace" if the environment variable is not set
TARGET_FOLDER="${TARGET_FOLDER:-workspace}"
OUTPUT_DIR="output_pdfs"

# Reference directory for standard C2000 files
C2000WARE_DIR="./C2000Ware_4_01_00_00/device_support/f2837xd/examples/cpu1"

# --- GENERIC TEMPLATE LIST ---
# Add any files here that should be checked against the C2000Ware folder
# Separate file names with spaces
TEMPLATE_FILES=(
  "F28379dSerial.c"
  # "AnotherStandardFile.c"
  # "F2837xD_DefaultISR.c"
)

mkdir -p "$OUTPUT_DIR"

# 1. Find all unique directories that contain .c files at the specified depth
find "$TARGET_FOLDER" -mindepth 3 -maxdepth 3 -type f -name "*.c" -exec dirname {} \; | sort -u | while read -r dir; do
  
  # Extract the project folder name (e.g., "ProjectA")
  rel_path="${dir#"$TARGET_FOLDER"/}" 
  project_name=$(echo "$rel_path" | cut -d'/' -f1)
  
  echo "Processing folder: $dir (Project: $project_name)"
  
  # Initialize variables to control the exact merge order
  main_pdf=""
  template_pdfs=()
  other_pdfs=()
  all_temp_pdfs=()

  # Enable nullglob so the loop operates safely
  shopt -s nullglob
  
  # 2. Loop through every .c file in this specific directory
  for file in "$dir"/*.c; do
    filename=$(basename "$file")
    generate_pdf=false

    # Check if the file has a main function
    is_main=false
    if grep -q -P '\bmain\s*\(' "$file"; then
      is_main=true
    fi

    # Check if the file is in our template list
    is_template=false
    for tmpl in "${TEMPLATE_FILES[@]}"; do
      if [[ "$filename" == "$tmpl" ]]; then
        is_template=true
        break
      fi
    done

    # CONDITION 1: Is it in the Template list?
    if [ "$is_template" = true ]; then
      match_found=false
      for ref_file in "$C2000WARE_DIR"/*/cpu01/"$filename"; do
        if cmp -s "$file" "$ref_file"; then
          match_found=true
          break
        fi
      done

      if [ "$match_found" = false ]; then
        generate_pdf=true
        echo "  -> Including custom/modified $filename"
      else
        echo "  -> Skipping default C2000Ware $filename"
      fi

    # CONDITION 2: Does it contain a main function?
    elif [ "$is_main" = true ]; then
      generate_pdf=true
      echo "  -> Including $filename (contains main)"
    fi

    # 3. Generate HTML and individual PDF for the file
    if [ "$generate_pdf" = true ]; then
      base_name="${filename%.c}"
      
      temp_html="temp_${base_name}.html"
      temp_pdf="temp_${base_name}.pdf"
      
      # Generate HTML
      pygmentize -f html -O full,style=default,linenos=1 -l c -o "$temp_html" "$file"

      # Inject Code Composer Studio theme (Blue numbers)
      sed -i 's|</style>|\
        /* Numbers (Integers, Floats, Hex, Octal, etc.) */\
        .m, .mb, .mf, .mh, .mi, .mo, .il { color: #2A00FF !important; font-weight: normal !important; }\
      </style>|' "$temp_html"

      # Generate a single PDF for this specific file
      wkhtmltopdf --quiet --enable-local-file-access "$temp_html" "$temp_pdf"

      # --- ORDERING LOGIC ---
      # Sort the generated PDF into the correct variable/array
      if [ "$is_main" = true ]; then
        main_pdf="$temp_pdf"
      elif [ "$is_template" = true ]; then
        template_pdfs+=("$temp_pdf")
      else
        other_pdfs+=("$temp_pdf")
      fi
      
      all_temp_pdfs+=("$temp_pdf")
      
      # Clean up the HTML file immediately
      rm -f "$temp_html"
    fi
  done
  
  # Disable nullglob for safety
  shopt -u nullglob

  # 4. Assemble the final PDF array in the exact requested order
  ordered_pdfs=()
  if [ -n "$main_pdf" ]; then ordered_pdfs+=("$main_pdf"); fi
  ordered_pdfs+=("${template_pdfs[@]}")
  ordered_pdfs+=("${other_pdfs[@]}")

  # 5. If we generated PDFs, stitch them together using qpdf
  if [ ${#ordered_pdfs[@]} -gt 0 ]; then
    pdf_filename="${project_name}.pdf"
    
    # Merge all individual PDFs into the final output file
    qpdf --empty --pages "${ordered_pdfs[@]}" -- "$OUTPUT_DIR/$pdf_filename"
    
    echo "Successfully created combined PDF: $OUTPUT_DIR/$pdf_filename"
    
    # Clean up the temporary single-page PDFs
    rm -f "${all_temp_pdfs[@]}"
  else
    echo "No matching files needed compiling in $dir"
  fi
  
  echo "---------------------------------------------------"
done