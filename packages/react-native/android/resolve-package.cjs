// Keep paths as arguments: inline Node expressions lose quotes through Windows Gradle.
process.stdout.write(require.resolve(process.argv[2] + '/package.json', {paths: [process.argv[3]]}));
