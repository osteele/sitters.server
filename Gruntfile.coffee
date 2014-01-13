fs = require 'fs'

module.exports = (grunt) ->
  coffeeFiles = ['**/*.coffee', '!node_modules/**/*', '!migrations/**/*', '!Gruntfile.*', '!outtakes.coffee']

  grunt.initConfig
    clean: build: ['build']

    coffeelint:
      app: coffeeFiles
      gruntfile: 'Gruntfile.coffee'
      options: max_line_length: { value: 120 }

    docco:
      debug:
        src: coffeeFiles
        options:
          output: 'build/docs/'

    express:
      default_option:
        port: 5000

    shell:
      promoteSecurityRules:
        options: {stdout: true}
        command: 'cp ./config/firebase-development-rules.coffee ./config/firebase-production-rules.coffee'

    watch:
      options:
        livereload: true
      docs:
        files: coffeeFiles
        tasks: ['docco']
      gruntfile:
        files: 'Gruntfile.coffee'
        tasks: ['coffeelint:gruntfile']
      securityRules:
        files: 'config/firebase-*-rules.coffee'
        tasks: ['compile-security-rules']

  require('load-grunt-tasks')(grunt)

  grunt.registerTask 'compile-security-rules', ->
    outputFile = 'build/firebase-security-rules.json'
    readRulesForEnvironment = (environment) ->
      path = "config/firebase-#{environment}-rules.coffee"
      require('coffee-script').eval(fs.readFileSync(path, 'utf8')).rules
    rules =
      development: readRulesForEnvironment('development')
      production: readRulesForEnvironment('production')
      $other:
        ".read": true
    fs.writeFileSync outputFile, JSON.stringify({rules}, null, 2) + "\n"

  grunt.registerTask 'docs', ['docco']
  grunt.registerTask 'lint', ['coffeelint']
  grunt.registerTask 'promote-firebase-rules', ['shell:promoteSecurityRules']
  # grunt.registerTask 'default', ['update', 'connect', 'autowatch']
