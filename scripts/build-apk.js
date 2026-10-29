const { execSync } = require('child_process');
const path = require('path');
const fs = require('fs');

const isWindows = process.platform === 'win32';
const androidDir = path.join(__dirname, '..', 'android');
const apkSource = path.join(
  androidDir,
  'app',
  'build',
  'outputs',
  'apk',
  'release',
  'app-release.apk'
);
const apkTarget = path.join(__dirname, '..', 'app-layoutsnative.apk');

function run(command, options = {}) {
  console.log(`\n> ${command}`);
  const shell = isWindows ? 'cmd.exe' : true;
  execSync(command, {
    stdio: 'inherit',
    cwd: options.cwd || androidDir,
    shell,
    ...options,
  });
}

try {
  const gradlew = isWindows
    ? path.join(androidDir, 'gradlew.bat')
    : './gradlew';
  const cleanCommand = `"${gradlew}" assembleRelease`;

  run(cleanCommand, { cwd: androidDir });

  if (!fs.existsSync(apkSource)) {
    console.error(`\nError: no se encontró la APK en ${apkSource}`);
    process.exit(1);
  }

  fs.copyFileSync(apkSource, apkTarget);
  console.log(`\n✅ APK copiada a: ${apkTarget}`);
} catch (error) {
  console.error('\n❌ Error al generar la APK:', error.message);
  process.exit(1);
}
