require 'rubygems'
require 'zip/zip'
require 'pp'

Zip::ZipInputStream::open("com-2.djrausch.finalcalculator.zip") do |io|
  while (entry = io.get_next_entry)
    pp entry
  end
end

Zip::ZipInputStream::open("samples/test-orig.docx") do |io|
  while (entry = io.get_next_entry)
    pp entry
  end
end

#Zip::ZipFile::foreach("com-2.djrausch.finalcalculator.zip") do |entry|
# pp entry.name
#end

#Zip::ZipFile.open(zipfile_name) do |zipfile|
#  puts zipfile.read("mimetype")
#end

