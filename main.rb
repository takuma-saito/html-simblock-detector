require 'nokogiri'
require "open-uri"
require 'kconv'

def remove_elem(doc)
  doc.xpath('//comment()').remove
  doc.xpath('//script').remove
end

def get_xpath(doc)
  doc
end

def inner_product(x, y)
  x.map do |k, v|
    (y.key?(k)) ? (y[k] * v) : 0
  end.reduce(&:+)
end

def calc(arr)
  return 0.0 if arr.empty?
  len = arr.map {|x|
    [x.values, x.values].transpose.map{|y| y.reduce(&:*)}.reduce(&:+)
  }.reduce(&:+).to_f
  val = arr.map { |x| arr.map {|y| inner_product(x, y)}.reduce(&:+) }.reduce(&:+)
  (val.to_f / len) * arr.size
end

def val_elem(doc)
  res = {}
  res[doc.name] = 1
  doc.attributes.each do |k, v|
    if k == 'class'
      v.value.split(" ").each do |n|
        res["#{doc.name}_class_#{n}"] = 1
      end
    end
  end
  res
end

def val(doc)
  case doc
  when Nokogiri::XML::Text
    nil # skip
  when Nokogiri::XML::NodeSet
    nil # skip
  when Nokogiri::XML::Element
    return nil if doc.name == "br"
    val_elem(doc)
  else
    raise "unknown attributes: #{doc.class}"
  end
end

def merge!(arr, x)
  x.each do |k, v|
    if arr.key? k
      arr[k] += v
    else
      arr[k] = v
    end
  end
  arr
end

def merge_hash(arr)
  arr.reduce {|accum, x| merge!(accum, x) unless x.nil?}
end

def dfs(doc)
  children = doc&.children
  return val(doc) if children.empty?
  arr = children.map do |elem|
    dfs(elem)
  end + [val(doc)]
  arr = arr.reject(&:nil?)
  if calc(arr) > 30.0
    puts doc.to_html
    puts calc(arr)
    p arr
    puts "=========="
  end
  hash = merge_hash(arr)
  return hash
end

read_from_url = -> (url) {
  open(url).read.toutf8
}
read_from_file = -> (file) {
  File.open(file).read  
}

html = read_from_url.(ARGV[0])

doc = Nokogiri::HTML html
remove_elem(doc)
$res = []
dfs(doc.xpath('//body'))

