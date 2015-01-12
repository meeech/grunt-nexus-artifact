http = require 'http'
fs = require 'fs'
Q = require 'q'
crypto = require 'crypto'
urlUtil = require 'url'
xml2js = require 'xml2js'

module.exports = (grunt) ->

  compress = require('grunt-contrib-compress/tasks/lib/compress')(grunt)

  downloadFile = (artifact, path, temp_path) ->
    deferred = Q.defer()

    # http.get artifact.buildUrl(), (res) ->

    #   file = fs.createWriteStream temp_path
    #   res.pipe file

    #   res.on 'error', (error) -> deferred.reject (error)
    #   file.on 'error', (error) -> deferred.reject (error)

    #   res.on 'end', ->
    grunt.util.spawn
      cmd: 'curl'
      args: "-o #{temp_path} #{artifact.buildUrl()}".split(' ')
    , (err, stdout, stderr) ->
      if err
        deferred.reject err
        return

      grunt.file.delete temp_path

      filePath = "#{path}/.downloadedArtifacts"
      downloadedArtifacts[artifact.toString()] = new Date()
      grunt.file.write filePath, JSON.stringify(downloadedArtifacts)

      deferred.resolve()

    deferred.promise

  downloadSnapshot = (artifact, path, temp_path, snapshotSuffix) ->
    deferred = Q.defer()

    temp_path = temp_path.replace "SNAPSHOT", snapshotSuffix

    grunt.util.spawn
      cmd: 'curl'
      args: "-o #{temp_path} #{artifact.buildSnapshotUrl(snapshotSuffix)}".split(' ')
    , (err, stdout, stderr) ->
      if err
        deferred.reject err
        return

      filePath = "#{path}/.downloadedArtifacts"
      downloadedArtifacts = {}
      downloadedArtifacts[artifact.toString().replace("SNAPSHOT", snapshotSuffix) ] = new Date()
      grunt.file.write filePath, JSON.stringify(downloadedArtifacts)

      deferred.resolve()

    deferred.promise

  downloadMetadata = (artifact, path, temp_path) ->
    deferred = Q.defer()

    # http.get artifact.buildUrl(), (res) ->

    #   file = fs.createWriteStream temp_path
    #   res.pipe file

    #   res.on 'error', (error) -> deferred.reject (error)
    #   file.on 'error', (error) -> deferred.reject (error)

    #   res.on 'end', ->
    grunt.util.spawn
      cmd: 'curl'
      args: "-o #{temp_path} #{artifact.buildMavenMetadataUrl()}".split(' ')
    , (err, stdout, stderr) ->

      if err
        deferred.reject err
        return
      
      deferred.resolve()

    deferred.promise

  uploadCurl = (filename, url, credentials) ->
    deferred = Q.defer()
    authStr = if credentials.username then "-u #{credentials.username}:#{credentials.password}"  else ''

    grunt.util.spawn
      cmd: 'curl'
      args: "-T #{filename} #{authStr} #{url}".split ' '
    , (err, result, code) ->
      grunt.log.writeln "Uploaded #{filename.cyan}"
      deferred.reject err if err

      deferred.resolve()

    deferred.promise

  upload = (data, url, credentials, isFile = true) ->
    deferred = Q.defer()

    options = grunt.util._.extend urlUtil.parse(url), {method: 'PUT'}
    if credentials.username
      options = grunt.util._.extend options, {auth: credentials.username + ":" + credentials.password}

    request = http.request options

    if isFile
      file = fs.createReadStream(data)
      destination = file.pipe(request)

      destination.on 'end', ->
        grunt.log.writeln "Uploaded #{data.cyan}"
        deferred.resolve()

      destination.on 'error', (error) -> deferred.reject error
      file.on 'error', (error) -> deferred.reject error
      request.on 'error', (error) -> deferred.reject error
    else
      request.end data
      deferred.resolve()

    deferred.promise

  publishFile = (options, filename, urlPath) ->
    deferred = Q.defer()

    generateHashes(options.path + filename).then (hashes) ->

      url = urlPath + filename

      # allow upload through curl
      uploadFn = if options.curl then uploadCurl else upload

      promises = [
        uploadFn options.path + filename, url, options.credentials
        upload hashes.sha1, "#{url}.sha1", options.credentials, false
        upload hashes.md5, "#{url}.md5", options.credentials, false
      ]

      Q.all(promises).then () ->
        deferred.resolve()
      .fail (error) ->
        deferred.reject error
    .fail (error) ->
      deferred.reject error

    deferred.promise

  generateHashes = (file) ->
    deferred = Q.defer()

    md5 = crypto.createHash 'md5'
    sha1 = crypto.createHash 'sha1'

    stream = fs.ReadStream file

    stream.on 'data', (data) ->
      sha1.update data
      md5.update data

    stream.on 'end', (data) ->
      hashes =
        md5: md5.digest 'hex'
        sha1: sha1.digest 'hex'
      deferred.resolve hashes

    stream.on 'error', (error) ->
      deferred.reject error

    deferred.promise

  return {

  ###*
  * Download an nexus artifact and extract it to a path
  * @param {NexusArtifact} artifact The nexus artifact to download
  * @param {String} path The path the artifact should be extracted to
  *
  * @return {Promise} returns a Q promise to be resolved when the file is done downloading
  ###
  download: (artifact, path) ->
    deferred = Q.defer()

    grunt.file.mkdir path

    if artifact.isSnapshot()
      # Download Maven Metadata XML file to determine latest SNAPSHOT
      temp_path = "#{path}/maven-metadata.xml"
      grunt.log.writeln "Downloading maven-metadata.xml for #{artifact.name}"
      downloadMetadata( artifact, path, temp_path ).then( ->
        grunt.log.writeln "Parsing maven-metadata.xml for #{artifact.name}"
        fs.readFile temp_path, (err, data) ->
          parser = new xml2js.Parser()
          parser.parseString data, (err, result) ->
            grunt.file.delete temp_path
            
            if !result.metadata.versioning || !result.metadata.versioning[0].snapshot
              deferred.reject "Insufficient data in Maven metadata to resolve snapshot version"

            suffix = result.metadata.versioning[0].snapshot[0].timestamp[0] + "-" + result.metadata.versioning[0].snapshot[0].buildNumber[0];
            
            filePath = "#{path}/.downloadedArtifacts"
            if grunt.file.exists(filePath)
              downloadedArtifacts = grunt.file.readJSON(filePath)
              if downloadedArtifacts[artifact.toString().replace("SNAPSHOT", suffix)]
                grunt.log.writeln "Up-to-date: #{artifact}"
                deferred.resolve( temp_path )

            grunt.log.writeln "Downloading #{artifact.buildSnapshotUrl(suffix)}"
            temp_path = "#{path}/#{artifact.buildArtifactUri()}"
            downloadSnapshot(artifact, path, temp_path, suffix).then( ->
              console.log "Snapshot download complete of #{artifact.name}"
              deferred.resolve( temp_path )
            ).fail ( error ) ->
              deferred.reject error
      ).fail ( error ) ->
        deferred.reject error
    else
      filePath = "#{path}/.downloadedArtifacts"
      if grunt.file.exists(filePath)
        downloadedArtifacts = grunt.file.readJSON(filePath)
        if downloadedArtifacts[artifact.toString()]
          grunt.log.writeln "Up-to-date: #{artifact}"
          deferred.resolve( temp_path )

      temp_path = "#{path}/#{artifact.buildArtifactUri()}"
      grunt.log.writeln "Downloading #{artifact.buildUrl()}"

      downloadFile(artifact, path, temp_path).then( ->
        deferred.resolve(temp_path)
      ).fail (error) ->
        deferred.reject error

    deferred.promise

  ###*
  * Publish a path to nexus
  * @param {NexusArtifact} artifact The nexus artifact to publish to nexus
  * @param {String} path The path to publish to nexus
  *
  * @return {Promise} returns a Q promise to be resolved when the artifact is done being published
  ###
  publish: (artifact, files, options) ->
    deferred = Q.defer()
    filename = artifact.buildArtifactUri()
    archive = "#{options.path}#{filename}"

    compress.options =
      archive: archive
      mode: compress.autoDetectMode(archive)

    compress.tar files, () ->
      publishFile(options, filename, artifact.buildUrlPath()).then( ->
        deferred.resolve()
      ).fail (error) ->
        deferred.reject error

    deferred.promise

  ###*
  * Verify the integrity of the tar file published by this grunt task after publishing.
  * @param {NexusArtifact} artifact to publish to nexus
  * @param {String} path to publish to nexus
  *
  * @return {Promise} returns a Q promise to be resolved when the artifact is done being downloaded & unpacked
  ###
  verify: (artifact, path) ->

    deferred = Q.defer()

    @download(artifact, path).then( () ->
        grunt.log.writeln "Download and unpack of archive successful"
        deferred.resolve()
      ).fail ( (err) ->
        grunt.log.writeln "There was a problem downloading and unpacking the created archive. Error: #{ err }"
        deferred.reject err
      )

    deferred.promise

  }