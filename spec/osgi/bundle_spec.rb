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

require File.join(File.dirname(__FILE__), '../spec_helpers')

describe OSGi::Version do
  it 'should initialize itself from a string' do
    version = OSGi::Version.new("1.0.0.qualifier")
    version.major.should eql("1")
    version.minor.should eql("0")
    version.tiny.should eql("0")
    version.qualifier.should eql("qualifier")
  end  
  
  it 'should accept versions without a qualifier' do
    version = OSGi::Version.new("1.0.0")
    version.major.should eql("1")
    version.minor.should eql("0")
    version.tiny.should eql("0")
    version.qualifier.should be_nil
  end
  
  it 'should accept versions without a qualifier and a tiny digit' do
    version = OSGi::Version.new("1.0")
    version.major.should eql("1")
    version.minor.should eql("0")
    version.tiny.should be_nil
    version.qualifier.should be_nil
  end
  
  it 'should accept versions without a qualifier, a minor and a tiny digit' do
    version = OSGi::Version.new("1")
    version.major.should eql("1")
    version.minor.should be_nil
    version.tiny.should be_nil
    version.qualifier.should be_nil
  end
  
  it 'should raise an exception if no major digit is given' do
    lambda { OSGi::Version.new(".0.0.qualifier") }.should raise_error(RuntimeError, /Invalid version:/)
  end
  
  it 'should raise an exception if no minor digit is given' do
    lambda { OSGi::Version.new("1..0.qualifier") }.should raise_error(RuntimeError, /Invalid version:/)
  end
  
  it 'should raise an exception if no tiny digit is given' do
    lambda { OSGi::Version.new("1.0..qualifier") }.should raise_error(RuntimeError, /Invalid version:/)
  end
  
  it 'should have a string representation' do
    version = OSGi::Version.new("1.0.0.qualifier")
    version.to_s.should eql("1.0.0.qualifier")
    version.major = 2
    version.to_s.should eql("2.0.0.qualifier")
  end
  
  it 'should compare with other versions' do
    (OSGi::Version.new('1.0.0') < "2.0.0").should be_true
    (OSGi::Version.new('1.9.9') > "2.0.0").should be_false
    (OSGi::Version.new('1.54.112') < "2.2.0").should be_true
    (OSGi::Version.new('1.0.3') > "1.0.2").should be_true
    (OSGi::Version.new('2.3.4') == "2.3.4").should be_true
    (OSGi::Version.new('2.3.4') <=> "2.3.4").should eql(0)
  end
  
  it 'should compare with nil' do
    (OSGi::Version.new('1.0.0') <=> nil).should eql(1)
  end
end

describe OSGi::VersionRange do
  
  it 'should be able to parse version ranges' do
    OSGi::VersionRange.parse("[1.0.0,2.0.0)").should be_instance_of(OSGi::VersionRange)
    OSGi::VersionRange.parse("[1.0.0,2.0.0]").should be_instance_of(OSGi::VersionRange)
    OSGi::VersionRange.parse("(1.0.0,2.0.0)").should be_instance_of(OSGi::VersionRange)
    OSGi::VersionRange.parse("(1.0.0,2.0.0]").should be_instance_of(OSGi::VersionRange)
    OSGi::VersionRange.parse("[1.0.02.0.0)").should be_false
    OSGi::VersionRange.parse("[1.0.0,2.0.0").should be_false
    OSGi::VersionRange.parse("1.0.0,2.0.0)").should be_false
    OSGi::VersionRange.parse("[1.0,0,2.0.0)").should be_false
  end
  
  it 'should be able to tell if a version is in a range' do
    range = OSGi::VersionRange.parse("[1.0.0,2.0.0)")
    range.in_range("1.5.0.20080607").should be_true
    range.in_range("2.0.0.20080607").should be_false
    range.in_range("1.0.0.20080607").should be_true
    range.in_range("0.9.0.20080607").should be_false
    range = OSGi::VersionRange.parse("(1.0.0,2.0.0]")
    range.in_range("2.0.0.20080607").should be_true
    range.in_range("1.0.0.20080607").should be_false
  end
  
  it 'should have a String representation' do
    range = OSGi::VersionRange.parse("[1.0.0,2.0.0)")
    range.to_s.should eql("[1.0.0,2.0.0)")
    r2 = OSGi::VersionRange.new
    r2.min = OSGi::Version.new("1.0.0")
    r2.max = OSGi::Version.new("2.0.0")
    r2.min_inclusive = true
    r2.to_s.should eql("[1.0.0,2.0.0)")
  end
  
end

describe OSGi::Bundle do
  before :all do
    manifest = <<-MANIFEST
Manifest-Version: 1.0
Bundle-ManifestVersion: 2
Bundle-SymbolicName: org.eclipse.core.resources; singleton:=true
Bundle-Version: 3.5.1.R_20090912
Bundle-ActivationPolicy: Lazy
MANIFEST
    @bundle = OSGi::Bundle.fromManifest(Manifest.read(manifest), ".")
    manifest2 = <<-MANIFEST
Manifest-Version: 1.0
Bundle-ManifestVersion: 2
Bundle-SymbolicName: org.eclipse.core.resources.x86; singleton:=true
Bundle-Version: 3.5.1.R_20090912
Bundle-ActivationPolicy: Lazy
Fragment-Host: org.eclipse.core.resources
MANIFEST
    @fragment = OSGi::Bundle.fromManifest(Manifest.read(manifest2), ".")
  end
  
  it 'should read from a manifest' do
    @bundle.name.should eql("org.eclipse.core.resources")
    @bundle.version.to_s.should eql("3.5.1.R_20090912")
    @bundle.lazy_start.should be_true
    @bundle.start_level.should eql(4)
  end
  
  it 'should be transformed as an artifact' do
    @bundle.to_s.should eql("osgi:org.eclipse.core.resources:jar:3.5.1.R_20090912")
  end
  
  it 'should recognize itself as a fragment' do
    @fragment.fragment?.should be_true
  end
  
end