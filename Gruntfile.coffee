module.exports = (grunt) ->
  grunt.initConfig
    clean: build: ['build']

    coffeelint:
      app: ['**/*.coffee', '!node_modules/**/*']
      gruntfile: 'Gruntfile.coffee'
      options: max_line_length: { value: 120 }

    docco:
      debug:
        src: ['**/*.coffee', '!node_modules/**/*', '!migrations/**/*', '!Gruntfile.*']
        options:
          output: 'build/docs/'

    express:
      default_option:
        port: 5000

    watch:
      options:
        livereload: true
      docs:
        files: ['**/*.coffee', '!node_modules/**/*', '!migrations/**/*', '!Gruntfile.*']
        tasks: ['docco']
      gruntfile:
        files: 'Gruntfile.coffee'
        tasks: ['coffeelint:gruntfile']

  require('load-grunt-tasks')(grunt)

  grunt.registerTask 'docs', ['docco']
  # grunt.registerTask 'default', ['update', 'connect', 'autowatch']
