# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with this
# work for additional information regarding copyright ownership.  The ASF
# licenses this file to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.  See the
# License for the specific language governing permissions and limitations under
# the License.

module OSGi #:nodoc:

  OSGI_GROUP_ID = "osgi"

  class Version

    attr_accessor :major, :minor, :tiny, :qualifier

    def initialize(string)
      digits = string.gsub(/\"/, '').split(".")
      @major = digits[0]
      @minor = digits[1]
      @tiny = digits[2]
      @qualifier = digits[3]
      raise "Invalid version: " + self.to_s if @major == ""
      raise "Invalid version: " + self.to_s if @minor == "" && (!@tiny != "" || !@qualifier != "")
      raise "Invalid version: " + self.to_s if @tiny == "" && !@qualifier != ""
    end


    def to_s
      str = [major]
      str << minor if minor
      str << tiny if minor && tiny
      str << qualifier if minor && tiny && qualifier
      str.compact.join(".")
    end

    def <=>(other)
      if other.is_a? String
        other = Version.new(other)
      elsif other.nil?
        return 1
      end

      [:major, :minor, :tiny, :qualifier].each do |digit|
        return 0 if send(digit).nil? 

        comparison = send(digit) <=> other.send(digit)
        if comparison != 0
          return comparison
        end

      end
      return 0
    end

    def <(other)
      (self.<=>(other)) == -1
    end

    def >(other)
      (self.<=>(other)) == 1
    end

    def ==(other)
      (self.<=>(other)) == 0
    end

    def <=(other)
      (self.==(other)) || (self.<(other))
    end

    def >=(other)
      (self.==(other)) || (self.>(other))
    end
  end

  class VersionRange

    attr_accessor :min, :max, :min_inclusive, :max_inclusive

    def self.parse(string)
      return string if string.is_a?(VersionRange)
      if !string.nil? && (match = string.match /\s*([\[|\(])([0-9|\.]*),([0-9|\.]*)([\]|\)])/)
        range = VersionRange.new
        range.min = Version.new(match[2])
        range.max = Version.new(match[3])
        range.min_inclusive = match[1] == '['
        range.max_inclusive = match[4] == ']'
        range
      else
        false
      end
    end

    def to_s
      "#{ min_inclusive ? '[' : '('}#{min},#{max}#{max_inclusive ? ']' : ')'}"
    end

    def in_range(version)
      (min_inclusive ? min <= version : min < version) && (max_inclusive ? max >= version : max > version)
    end
  end

  class BundlePackage
    attr_accessor :name, :version, :bundles, :imports
    
    def initialize(name, version, args = {})
      @name= name
      @version = VersionRange.parse(version) || (version.nil? ? nil : version.gsub(/\"/, ''))
      @bundles = args[:bundles] || []
      @imports = args[:imports] || []
    end

    def resolve_matching_artifacts(project)
      resolved = case
      when version.is_a?(VersionRange) then
        project.osgi.registry.resolved_containers.collect {|i| i.find(:exports_package => name).select {|b| version.in_range(b.version)}}
      when version.nil? then
        project.osgi.registry.resolved_containers.collect {|i| i.find(:exports_package => name)}
      else
        project.osgi.registry.resolved_containers.collect {|i| i.find(:exports_package => name).select {|b| version == b.version}}
      end
      resolved.flatten.compact.collect{|b| b.dup}
    end
    
    def resolve(project, bundles = resolve_matching_artifacts(project))
      bundles = case bundles.size
      when 0 then []
      when 1 then bundles
      else
        bundles = OSGi::PackageResolvingStrategies.send(project.osgi.options.bundle_resolving_strategy, name, bundles)
      end
      bundles
    end
    
    def to_s
      "Import Package #{name} with version #{version}"
    end

  end

  class Bundle
    include Buildr::ActsAsArtifact

    #Keys used in the MANIFEST.MF file
    B_NAME = "Bundle-SymbolicName"
    B_REQUIRE = "Require-Bundle"
    B_IMPORT_PKG = "Import-Package"
    B_EXPORT_PKG = "Export-Package"
    B_FRAGMENT_HOST = "Fragment-Host"
    B_VERSION = "Bundle-Version"
    B_DEP_VERSION = "bundle-version"
    B_RESOLUTION = "resolution"
    B_LAZY_START = "Bundle-ActivationPolicy"
    B_OLD_LAZY_START = "Eclipse-LazyStart"
    
    # Creates itself by loading from the manifest file passed to it as a hash
    # Finds the name and version, and populates a list of dependencies.
    def self.fromManifest(manifest, jarFile) 
      if manifest.first[B_NAME].nil?
        warn "Could not find the name of the bundle represented by #{jarFile}"
        return nil
      end
      
      #see http://aspsp.blogspot.com/2008/01/wheressystembundlejarfilecont.html for the system.bundle trick.
      #key.strip: sometimes there is a space between the comma and the name of the bundle.
      #Add the required bundles:
      bundles = []
      manifest.first[B_REQUIRE].each_pair {|key, value| bundles << Bundle.new(key.strip, value[B_DEP_VERSION], {:optional => value[B_RESOLUTION] == "optional"}) unless "system.bundle" == key} unless manifest.first[B_REQUIRE].nil?
      exports = manifest.first[B_EXPORT_PKG]
      #Parse the version
      version = manifest.first[B_VERSION].nil? ? nil : manifest.first[B_VERSION].keys.first
      
      #Read the imports
      imports = []
      manifest.first[B_IMPORT_PKG].each_pair {|key, value| imports << BundlePackage.new(key.strip, value[B_DEP_VERSION])} unless manifest.first[B_IMPORT_PKG].nil?
      
      #Read the imported packages
      
      bundle = Bundle.new(manifest.first[B_NAME].keys.first, version, {:file => jarFile, :bundles => bundles, :imports => imports, :exported_packages => exports})
      if !manifest.first[B_LAZY_START].nil? 
        # We look for the value of BundleActivationPolicy: lazy or nothing usually. 
        # lazy may be spelled Lazy too apparently, so we downcase the string in case.
        bundle.lazy_start = "lazy" == manifest.first[B_LAZY_START].keys.first.strip.downcase
      else
        bundle.lazy_start = "true" == manifest.first[B_OLD_LAZY_START].keys.first.strip unless manifest.first[B_OLD_LAZY_START].nil?
      end
      if (bundle.lazy_start)
        bundle.start_level = 4
      else
        bundle.start_level = 1
      end
      
      bundle.fragment = Bundle.new(manifest.first[B_FRAGMENT_HOST].keys.first.strip, 
        manifest.first[B_FRAGMENT_HOST].values.first[B_DEP_VERSION]) unless (manifest.first[B_FRAGMENT_HOST].nil?)
      return bundle
    end

    

    # Attributes of a bundle, derived from its manifest
    # The name is always the symbolic name
    # The version is either the exact version of the bundle or the range in which the bundle would be accepted.
    # The file is the location of the bundle on the disk
    # The optional tag is present on bundles resolved as dependencies, marked as optional.
    # The start level is deduced from the bundles.info file. Default is 1.
    # The lazy start is found in the bundles.info file
    attr_accessor :name, :version, :bundles, :file, :optional, :start_level, :lazy_start, :group, :fragment, :exported_packages, :imports

    alias :id :name

    def initialize(name, version, args = {:file => nil, :bundles=>[], :imports => [], :optional => false})
      @name = name
      @version = VersionRange.parse(version) || (version.nil? ? nil : version.gsub(/\"/, ''))
      @bundles = args[:bundles] || []
      @imports = args[:imports] || []
      @exported_packages = args[:exported_packages] || []
      @file = args[:file]
      @optional = args[:optional]
      @start_level = 4
      @type = "jar" #it's always a jar, even if it is a directory: we will jar it for Maven.
      @group = OSGI_GROUP_ID
    end

    def resolve_matching_artifacts(project)
      if version.is_a? VersionRange
        return project.osgi.registry.resolved_containers.collect {|i| 
          i.find(:name => name).select {|b| version.in_range(b.version)}}.flatten.compact.collect{|b| b.dup }
      elsif version.nil?
        return project.osgi.registry.resolved_containers.collect {|i| 
          i.find(:name => name)}.flatten.compact.collect{|b| b.dup }
      else
        project.osgi.registry.resolved_containers.collect {|i| 
        i.find(:name => name, :version => version)
        }.flatten.compact.collect{|b| b.dup }
      end
    end

    def fragment?
      !fragment.nil?
    end

    def to_s
       to_spec()
    end

    def to_yaml(opts = {})
      to_s.to_yaml(opts)
    end

    def <=>(other)
      if other.is_a?(Bundle)
       return to_s <=> other.to_s
      else
        return to_s <=> other
      end
    end

    def resolve(project, bundles = resolve_matching_artifacts(project))
      osgi = self.dup
      nil if !osgi.resolve!(project, bundles)
      osgi
    end

    def resolve!(project, bundles = resolve_matching_artifacts(project))
      bundle = case bundles.size
      when 0 then nil
      when 1 then bundles.first
      else
        OSGi::BundleResolvingStrategies.send(project.osgi.options.bundle_resolving_strategy, bundles)
      end
      if bundle.nil?
        warn "Could not resolve bundle for #{self.to_s}" 
        return false
      end
      @name = bundle.name
      @version = bundle.version
      @bundles = bundle.bundles
      @file = bundle.file
      @optional = bundle.optional
      @start_level = bundle.start_level
      @group = bundle.group

      true
    end

    def fragments(project)
      project.osgi.registry.resolved_containers.collect {|i| 
        i.find_fragments(:host => name).select{|f|
          if f.fragment.version.is_a? VersionRange
            f.fragment.version.in_range(version)
          elsif f.fragment.version.nil?
            true
          else
            f.fragment.version == version 
          end
          }
        }.flatten.compact.collect{|b| b.dup }
      end

    end
  end