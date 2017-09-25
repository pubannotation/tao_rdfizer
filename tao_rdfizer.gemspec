Gem::Specification.new do |s|
  s.name        = 'tao_rdfizer'
  s.version     = '0.9.0'
  s.summary     = 'A RDF statement generator for annotations in the PubAnnotation JSON format.'
  s.date        = Time.now.utc.strftime("%Y-%m-%d")
  s.description = "It uses TAO (text annotation ontology) for representation of annotations to text."
  s.authors     = ["Jin-Dong Kim"]
  s.email       = 'jindong.kim@gmail.com'
  s.files       = ["lib/tao_rdfizer.rb", "view/prefixes_ttl.erb", "view/tao_annotations_ttl.erb", "view/tao_spans_ttl.erb"]
  s.executables << 'tao_rdfizer'
  s.homepage    = 'https://github.com/pubannotation/tao_rdfizer'
  s.license     = 'MIT'
end