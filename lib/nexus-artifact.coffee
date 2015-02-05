
module.exports = (grunt) -> class NexusArtifact

  _ = grunt.util._

  # If an ID string is provided, this will return a config object suitable for creation of a NexusArtifact object
  @fromString = (idString) ->
    config = {}
    [config.group_id, config.name, config.ext, config.version] = idString.split(':')
    return config

  constructor: (config) ->
    {@url, @base_path, @repository, @group_id, @name, @version, @ext, @versionPattern} = config

  toString: () ->
    [@group_id, @name, @ext, @version].join(':')

  buildUrlPath: () ->
    _.compact(_.flatten([
      @url
      @base_path
      @repository
      @group_id.split('.')
      @name
      "#{@version}/"
    ])).join('/')

  isSnapshot: () ->
    /SNAPSHOT$/.test("#{@version}")


  buildMavenMetadataUrl: () ->
    "#{@buildUrlPath()}maven-metadata.xml"

  buildUrl: () ->
    "#{@buildUrlPath()}#{@buildArtifactUri()}"

  buildSnapshotUrl: (version) ->
    "#{@buildUrlPath()}#{@buildArtifactSnapshotUri(version)}"

  buildArtifactUri: () ->
    @versionPattern.replace /%([ave])/g, ($0, $1) =>
      { a: @name, v: @version, e: @ext }[$1]

  buildArtifactSnapshotUri: (suffix) ->
    @versionPattern.replace /%([ave])/g, ($0, $1) =>
      { a: @name, v: suffix, e: @ext }[$1]
