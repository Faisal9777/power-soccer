import os

# Name of the final master file
output_filename = "project_code.txt"

print("Scanning all subfolders for GDScript files...")
total_files = 0

with open(output_filename, "w", encoding="utf-8") as outfile:
    # os.walk automatically dives into every single subfolder
    for root, dirs, files in os.walk("."):
        
        # Optional: Skip Godot's internal .godot folder to speed things up
        if ".godot" in root:
            continue
            
        for file in files:
            # Strictly target ONLY .gd files
            if file.endswith(".gd"):
                # Get the exact path (e.g., ./Scenes/Player/player.gd)
                file_path = os.path.join(root, file)
                
                # Write a clean, visible header for your Notebook
                outfile.write(f"\n\n=========================================\n")
                outfile.write(f"FILE: {file} \n")
                outfile.write(f"PATH: {file_path}\n")
                outfile.write(f"=========================================\n\n")
                
                # Read the script and dump it into the master text file
                try:
                    with open(file_path, "r", encoding="utf-8") as infile:
                        outfile.write(infile.read())
                    total_files += 1
                    print(f"Successfully extracted: {file_path}")
                except Exception as e:
                    outfile.write(f"[Error reading file {file_path}: {e}]\n")

print(f"\n✨ Done! Extracted {total_files} GDScript files into '{output_filename}'.")