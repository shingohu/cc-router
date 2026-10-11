const fs = require('fs')
const path = require('path')
const { execFileSync } = require('child_process')

const disableEnvironment = 'CCROUTER_DISABLE_HVIGOR_PREFLIGHT'

function decodePropertyValue(value) {
  return value.replace(/\\([\\:= ])/g, '$1')
}

function resolveFlutterSdk(flutterProjectPath) {
  const propertiesPath = path.join(
    flutterProjectPath,
    'ohos',
    'local.properties'
  )
  if (!fs.existsSync(propertiesPath)) {
    throw new Error(
      `CCRouter Hvigor preflight cannot find ${propertiesPath}. ` +
      'Run Flutter dependency resolution before building with DevEco Studio.'
    )
  }
  const sdkLine = fs.readFileSync(propertiesPath, 'utf8')
    .split(/\r?\n/)
    .find(line => /^\s*flutter\.sdk\s*=/.test(line))
  if (!sdkLine) {
    throw new Error(
      `CCRouter Hvigor preflight cannot resolve flutter.sdk from ${propertiesPath}.`
    )
  }
  return decodePropertyValue(sdkLine.slice(sdkLine.indexOf('=') + 1).trim())
}

function resolveDartExecutable(flutterProjectPath) {
  const flutterSdk = resolveFlutterSdk(flutterProjectPath)
  const executable = path.join(
    flutterSdk,
    'bin',
    'cache',
    'dart-sdk',
    'bin',
    process.platform === 'win32' ? 'dart.exe' : 'dart'
  )
  if (!fs.existsSync(executable)) {
    throw new Error(
      `CCRouter Hvigor preflight cannot find the resolved Dart SDK: ${executable}.`
    )
  }
  return executable
}

function ccrouterBuildPreflight(flutterProjectPath) {
  if (process.env[disableEnvironment] === '1') {
    console.info(
      `CCRouter Hvigor preflight disabled by ${disableEnvironment}=1.`
    )
    return
  }
  const projectRoot = path.resolve(flutterProjectPath)
  const dart = resolveDartExecutable(projectRoot)
  const args = [
    'run',
    '--verbosity=error',
    'ccrouter_generator:ccrouter',
    'pub-hook',
    'run',
    '--project-root',
    projectRoot,
    '--pub-command',
    'build'
  ]
  try {
    execFileSync(dart, args, {
      cwd: projectRoot,
      env: process.env,
      stdio: 'inherit'
    })
  } catch (error) {
    const status = error && Number.isInteger(error.status)
      ? ` (exit ${error.status})`
      : ''
    throw new Error(`CCRouter Hvigor preflight failed${status}.`)
  }
}

module.exports = {
  ccrouterBuildPreflight,
  resolveDartExecutable
}
