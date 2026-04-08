#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e 

# Default to "workspace" if the environment variable is not set
TARGET_FOLDER="${TARGET_FOLDER:-workspace}"
OUTPUT_DIR="output_pdfs"

# Reference directory for standard C2000 files (Using forward slashes for Linux)
C2000WARE_DIR="./C2000Ware_4_01_00_00/device_support/f2837xd/examples/cpu1"

mkdir -p "$OUTPUT_DIR"

# Find .c files exactly 3 subfolders deep
find "$TARGET_FOLDER" -mindepth 3 -maxdepth 3 -type f -name "*.c" | while read -r file; do
  
  # Get just the filename (e.g., "main.c" or "F28379dSerial.c")
  filename=$(basename "$file")
  generate_pdf=false

  # CONDITION 1: Is it the Serial library file?
  if [[ "$filename" == "F28379dSerial.c" ]]; then
    match_found=false
    
    # Enable nullglob so the loop doesn't fail if the C2000Ware path doesn't exist
    shopt -s nullglob
    for ref_file in "$C2000WARE_DIR"/*/cpu01/F28379dSerial.c; do
      
      # 'cmp -s' operates silently and returns 0 if files are perfectly identical
      if cmp -s "$file" "$ref_file"; then
        match_found=true
        break # We found an exact match, no need to keep checking
      fi
    done
    shopt -u nullglob # Disable nullglob

    # If no exact match was found, we want to compile it
    if [ "$match_found" = false ]; then
      generate_pdf=true
      echo "Converting: Found custom/modified $filename in $file"
    else
      echo "Skipping: Exact C2000Ware match found for $file"
    fi

  # CONDITION 2: Does it contain a main function?
  elif grep -q -P '\bmain\s*\(' "$file"; then
    generate_pdf=true
    echo "Converting: Found main function in $file"
  fi

  # If either condition above was met, generate the PDF
  if [ "$generate_pdf" = true ]; then
    
    rel_path="${file#"$TARGET_FOLDER"/}" 
    project_name=$(echo "$rel_path" | cut -d'/' -f1)
    
    # 2. Strip the .c extension
    base_name="${filename%.c}"
    
    # 3. Create a clean, unique name: ProjectName_filename.pdf
    pdf_filename="${project_name}_${base_name}.pdf"
    
    # Generate HTML
    pygmentize -f html -O full,style=default,linenos=1 -l c -o temp.html "$file"

    # INJECT CODE COMPOSER STUDIO THEME (Now with Blue Numbers)
    sed -i 's|</style>|\
      /* Numbers (Integers, Floats, Hex, Octal, etc.) */\
      .m, .mb, .mf, .mh, .mi, .mo, .il { color: #2A00FF !important; font-weight: normal !important; }\
    </style>|' temp.html

    # Convert to PDF using the new unique filename
    wkhtmltopdf --enable-local-file-access temp.html "$OUTPUT_DIR/$pdf_filename"
    
    echo "Created: $OUTPUT_DIR/$pdf_filename"
  fi
done

# Clean up the temporary HTML file
rm -f temp.html