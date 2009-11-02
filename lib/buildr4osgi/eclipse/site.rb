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

module Buildr4OSGi

  class Category

    attr_accessor :features, :name, :label, :description 

    def initialize()
      @features = []
    end

  end

  module SiteWriter

    attr_accessor :description, :description_url, :categories

    # :nodoc:
    # When this module extends an object
    # the categories are initialized as empty arrays.
    #
    def SiteWriter.extend_object(obj)
      super(obj)
      obj.categories = []
    end

    #
    # http://help.eclipse.org/ganymede/index.jsp?topic=/org.eclipse.platform.doc.isv/reference/misc/update_sitemap.html
    #
    #<site pack200="false">
    #  <description url="http://www.example.com/DescriptionOfSite">Some description</description>
    #  <category-def name="some.id" label="Human readable label">
    #    <description>Some description</description>
    #  </category-def>
    #  <feature id="feature.id" version="2.0.3" url="features/myfeature.jar" patch="false">
    #    <category name="some.id"/>
    #  </feature>
    #</site>
    #
    def writeSiteXml()
      x = Builder::XmlMarkup.new(:target => out = "", :indent => 1)
      x.instruct!
      x.site(:pack200 => "false") {
        x.description(description, :url => description_url) if (description || description_url)
        for category in categories
          x.tag!("category-def", :name => category.name, :label => category.label) {
            x.description category.description if category.description
          }
        end

        
        f2c = feature_categories_map()
        f2c.each_pair { |feature, categories|
          x.feature(:id => feature.feature_id, :version => feature.version, :url => "features/#{feature.feature_id}_#{feature.version}.jar", :patch => false) {
            for category in categories
              x.category(:name => category.name)
            end
          }
        }
      }
    end  
    
    def feature_categories_map()
      f2c = {}
      categories.each do |category|
        for f in category.features
          f2c[f] ||= []
          f2c[f] << category
        end
      end
      f2c
    end
    
  end

  #Marker module common to all sites packaging tasks.
  #Tasks including this module are recognized internally as tasks packaging sites.
  module SitePackaging

  end

  class SiteTask < ::Buildr::Packaging::Java::JarTask
    include SitePackaging
    
    attr_accessor :site_xml
    
    def initialize(*args) #:nodoc:
      super
    end
    
    def generateSite(project)
      mkpath File.join(project.base_dir, 'target')
      feature_files = find_feature_files()
      if site_xml
        path("").include site_xml
      else
        File.open(File.join(project.base_dir, 'target', 'site.xml'), 'w') do |f|
          f.write(writeSiteXml())
        end
        path("").include File.join(project.base_dir, 'target', 'site.xml')
      end
      for feature in feature_files
        dir = File.join(project.base_dir, 'target', File.basename(feature.to_s, ".*"))
        
        feature_xml = nil
        feature_info = {}
        Zip::ZipFile.open(feature.to_s) do
          feature_xml = zip.find_entry("**/feature.xml").read
          feature_info[:id] = REXML::XPath.first(feature_xml, "/feature/@id")
          feature_info[:version] = REXML::XPath.first(feature_xml, "/feature/@version")
          p feature_info
        end
        unzip = Buildr::unzip(dir => feature.to_s)
        unzip.target.invoke
        p Dir.glob( File.join(project.base_dir, 'target', 'foo-1.0.0', '*'))
        featureHandling = file(dir)
        
        featureHandling.enhance do
          
          path("plugins").include File.join(dir, "plugins", "*")
        end
        Dir.glob(File.join(dir, "features")).each do |feature_dir|
          featureHandling.enhance([zip(File.join(feature_dir, "*")=>File.join(dir, "features", "#{File.basename(feature_dir)}.jar")).include(File.join(feature_dir, "*"))])
          featureHandling.enhance do
            path("features").include File.join(dir, "features", "#{File.basename(feature_dir)}.jar")
          end
        end
        
        featureHandling.invoke
      end
    end
    
    protected
    
    def find_feature_files
      feature_files = []
      unless @categories.nil? || @categories.empty?
        feature_categories_map.keys.uniq.each do |feature|
          artifact = case 
            when feature.is_a?(String)
              Buildr::artifact(feature)
            when feature.is_a?(Buildr::Project)
              Buildr::artifact(feature.package(:feature))
            else 
              feature
            end
          artifact.invoke
          feature_files << artifact
        end
      end
      feature_files
    end
  end

  # Methods added to project to package a project as a site
  #
  module ActAsSite
    include Extension

    protected

    # returns true if the project defines at least one site packaging.
    # We keep this method protected and we will call it using send.
    def is_packaging_site()
      packages.each {|package| return true if package.is_a?(::Buildr4OSGi::SitePackaging)}
      false
    end

    def package_as_site(file_name)
      task = SiteTask.define_task(file_name)
      task.extend SiteWriter
      task.enhance do |siteTask|
        siteTask.generateSite(project)
      end
      task
    end

    def package_as_site_spec(spec) #:nodoc:
      spec.merge(:type=>:zip, :id => name.split(":").last)
    end
  end
end

module Buildr #:nodoc:
  class Project #:nodoc:
    include Buildr4OSGi::ActAsSite
    
  end
end
