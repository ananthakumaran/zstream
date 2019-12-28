#!/usr/bin/env ruby
# encoding: utf-8

$VERBOSE = true
require "zip/zipfilesystem"
Zip::ZipFile.open("samples/test.docx") do |z| 
  s = z.file.read("_rels/.rels")
  z.file.delete("_rels/.rels")
  z.file.open("_rels/.rels","wb") { |f| f.write(s) }
end
