import fs from 'fs-extra';
import path from 'path';
import { fileURLToPath } from 'url';

// Get the directory name
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Make the build/index.js file executable
if (fs.existsSync(path.join(__dirname, '..', 'build', 'index.js'))) {
  fs.chmodSync(path.join(__dirname, '..', 'build', 'index.js'), '755');
}

// Copy the scripts directory to the build directory
try {
  // Ensure the build/scripts directory exists
  fs.ensureDirSync(path.join(__dirname, '..', 'build', 'scripts'));
  
  // Copy the godot_operations.gd file
  fs.copyFileSync(
    path.join(__dirname, '..', 'src', 'scripts', 'godot_operations.gd'),
    path.join(__dirname, '..', 'build', 'scripts', 'godot_operations.gd')
  );
  
  console.log('Successfully copied godot_operations.gd to build/scripts');

  // Copy addons/godot_mcp directory if it exists
  const addonsSource = path.join(__dirname, '..', 'addons', 'godot_mcp');
  const addonsTarget = path.join(__dirname, '..', 'build', 'addons', 'godot_mcp');
  if (fs.existsSync(addonsSource)) {
    fs.copySync(addonsSource, addonsTarget, { overwrite: true });
    console.log('Successfully copied addons/godot_mcp to build/addons/godot_mcp');
  }

} catch (error) {
  console.error('Error copying build assets:', error);
  process.exit(1);
}

console.log('Build scripts completed successfully!');
