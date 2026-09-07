import os

# Name of the final master file for scenes
output_filename = "project_scenes.txt"

print("Scanning all subfolders for Godot Scene (.tscn) files...")
total_files = 0

with open(output_filename, "w", encoding="utf-8") as outfile:
    # Digs into every subfolder automatically
    for root, dirs, files in os.walk("."):
        
        # Skip internal Godot cache folders
        if ".godot" in root:
            continue
            
        for file in files:
            # Strictly target ONLY .tscn files
            if file.endswith(".tscn"):
                # Get the exact path (e.g., ./Scenes/Player/player.tscn)
                file_path = os.path.join(root, file)
                
                # Write a clean header for your Notebook
                outfile.write(f"\n\n=========================================\n")
                outfile.write(f"SCENE FILE: {file} \n")
                outfile.write(f"PATH: {file_path}\n")
                outfile.write(f"=========================================\n\n")
                
                # Read the scene layout and dump it into the master text file
                try:
                    with open(file_path, "r", encoding="utf-8") as infile:
                        outfile.write(infile.read())
                    total_files += 1
                    print(f"Successfully extracted scene: {file_path}")
                except Exception as e:
                    outfile.write(f"[Error reading file {file_path}: {e}]\n")

print(f"\n✨ Done! Extracted {total_files} scene files into '{output_filename}'.")