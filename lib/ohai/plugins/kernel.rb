#
# Author:: Adam Jacob (<adam@opscode.com>)
# Author:: Benjamin Black (<nostromo@gmail.com>)
# Author:: Bryan McLellan (<btm@loftninjas.org>)
# Author:: Claire McQuin (<claire@opscode.com>)
# Author:: James Gartrell (<jgartrel@gmail.com>)
# Copyright:: Copyright (c) 2008, 2009, 2013 Opscode, Inc.
# Copyright:: Copyright (c) 2009 Bryan McLellan
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
# implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

Ohai.plugin(:Kernel) do
  provides "kernel", "kernel/modules"

  # common initial kernel attribute values
  def init_kernel
    kernel Mash.new
    [["uname -s", :name], ["uname -r", :release],
     ["uname -v", :version], ["uname -m", :machine]].each do |cmd, property|
      so = shell_out(cmd)
      kernel[property] = so.stdout.split($/)[0]
    end
    kernel
  end

  # common *bsd code for collecting modules data
  def bsd_modules(path)
    modules = Mash.new
    so = shell_out("#{Ohai.abs_path(path)}")
    so.stdout.lines do |line|
      #  1    7 0xc0400000 97f830   kernel
      if line =~ /(\d+)\s+(\d+)\s+([0-9a-fx]+)\s+([0-9a-fx]+)\s+([a-zA-Z0-9\_]+)/
        modules[$5] = { :size => $4, :refcount => $2 }
      end
    end
    modules
  end

  # windows
  def machine_lookup(sys_type)
    return "i386" if sys_type.eql?("X86-based PC")
    return "x86_64" if sys_type.eql?("x64-based PC")
    sys_type
  end

  # windows
  def os_lookup(sys_type)
    return "Unknown" if sys_type.to_s.eql?("0")
    return "Other" if sys_type.to_s.eql?("1")
    return "MSDOS" if sys_type.to_s.eql?("14")
    return "WIN3x" if sys_type.to_s.eql?("15")
    return "WIN95" if sys_type.to_s.eql?("16")
    return "WIN98" if sys_type.to_s.eql?("17")
    return "WINNT" if sys_type.to_s.eql?("18")
    return "WINCE" if sys_type.to_s.eql?("19")
    return nil
  end

  collect_data(:default) do
    kernel init_kernel
  end

  collect_data(:darwin) do
    kernel init_kernel
    kernel[:os] = kernel[:name]

    so = shell_out("sysctl -n hw.optional.x86_64")
    if so.stdout.split($/)[0].to_i == 1
      kernel[:machine] = 'x86_64'
    end

    modules = Mash.new
    so = shell_out("kextstat -k -l")
    so.stdout.lines do |line|
      if line =~ /(\d+)\s+(\d+)\s+0x[0-9a-f]+\s+0x([0-9a-f]+)\s+0x[0-9a-f]+\s+([a-zA-Z0-9\.]+) \(([0-9\.]+)\)/
        modules[$4] = { :version => $5, :size => $3.hex, :index => $1, :refcount => $2 }
      end
    end

    kernel[:modules] = modules
  end

  collect_data(:freebsd) do
    kernel init_kernel
    kernel[:os] = kernel[:name]

    so = shell_out("uname -i")
    kernel[:ident] = so.stdout.split($/)[0]
    so = shell_out("sysctl kern.securelevel")
    kernel[:securelevel] = so.stdout.split($/).select { |e| e =~ /kern.securelevel: (.+)$/ }

    kernel[:modules] = bsd_modules("/sbin/kldstat")
  end

  collect_data(:linux) do
    kernel init_kernel

    so = shell_out("uname -o")
    kernel[:os] = so.stdout.split($/)[0]

    modules = Mash.new
    so = shell_out("env lsmod")
    so.stdout.lines do |line|
      if line =~ /([a-zA-Z0-9\_]+)\s+(\d+)\s+(\d+)/
        modules[$1] = { :size => $2, :refcount => $3 }
      end
    end

    kernel[:modules] = modules
  end

  collect_data(:netbsd, :openbsd) do
    kernel init_kernel
    kernel[:os] = kernel[:name]

    so = shell_out("sysctl kern.securelevel")
    kernel[:securelevel] = so.stdout.split($/).select { |e| e =~ /kern.securelevel:\ (.+)$/ }

    kernel[:modules] = bsd_modules("/usr/bin/modstat")
  end

  collect_data(:solaris2) do
    kernel init_kernel

    so = shell_out("uname -s")
    kernel[:os] = so.stdout.split($/)[0]

    modules = Mash.new

    so = shell_out("modinfo")
    # EXAMPLE:
    # Id Loadaddr   Size Info Rev Module Name
    #  6  1180000   4623   1   1  specfs (filesystem for specfs)
    module_description =  /[\s]*([\d]+)[\s]+([a-f\d]+)[\s]+([a-f\d]+)[\s]+(?:[\-\d]+)[\s]+(?:[\d]+)[\s]+([\S]+)[\s]+\((.+)\)$/
    so.stdout.lines do |line|
      if mod = module_description.match(line)
        modules[mod[4]] = { :id => mod[1].to_i, :loadaddr => mod[2], :size => mod[3].to_i(16), :description => mod[5]}
      end
    end

    kernel[:modules] = modules
  end

  collect_data(:windows) do
    properties = {}
    shell_out("systeminfo").stdout.each_line do |line|
       kv = line.strip.split(/:\s+/, 2)
       properties[kv[0]] = kv[1]
    end

    kernel Mash.new

    kernel[:name] = properties["OS Name"]
    kernel[:release] = properties["OS Version"].split(' ')[0]
    kernel[:version] = properties["OS Version"]
    kernel[:os] = "WINNT"
    kernel[:machine] = "x86_64"

  end
end
