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
      compileSecurityRules:
        options: {stdout: true}
        command: './bin/coffee2json config/firebase-security-rules.coffee > build/firebase-security-rules.json'

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
        files: 'config/firebase-security-rules.coffee'
        tasks: ['shell:compileSecurityRules']

  require('load-grunt-tasks')(grunt)

  grunt.registerTask 'docs', ['docco']
  grunt.registerTask 'lint', ['coffeelint']
  grunt.registerTask 'compileSecurityRules', ['shell:compileSecurityRules']
  # grunt.registerTask 'default', ['update', 'connect', 'autowatch']
