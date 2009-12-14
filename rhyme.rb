%w[rack].each {|r| require r}

module Rhyme
	class Scope
		attr_accessor :request, :response
		def initialize env
			@request = Request.new env
			@response = Rack::Response.new
		end
	end
	class Request < Rack::Request
		attr_accessor :languages
		def initialize env
			@languages=env['HTTP_ACCEPT_LANGUAGE'].split(?,).map{ |s| s.split(?;) }.map{ |a| a.empty? ? nil : a.first.to_s.strip }.select{ |s| not (s.nil? or s.empty?) }
			super env
		end
	end
	class Router
		def initialize &block
			@mapper = {}
			instance_eval &block if block
		end
		def add_path path='/', cond={}, &block
			names = []
			path = path.gsub( /[.+?|(){}\[\]\\^$]/ ) { |c|
				"\\"+c
			}.gsub( /(\*)|(:\w+)/ ) { |c|
				if ?* === c
					names << '*'
					'(.*?)'
				else
					names << c[1..-1]
					'(\w*)'
				end
			}
			@mapper[path] ||= {re: Regexp.new( ?^ + path + ?$ ), variants: [] }
			@mapper[path][:variants] << {conditions: {}.merge(cond), argnames: names, block: block}
		end
		alias_method :any, :add_path
		{get: ['GET', 'HEAD'], head: 'HEAD', post: 'POST', put: 'PUT', delete: 'DELETE'}.each_pair do |reqmethod, conditions|
			define_method reqmethod do | path='/', cond={}, &block |
				any path, cond.merge( {method: conditions} ), & -> argnames, values {
					@params = argnames.zip(values).inject({}) { |a,v| a[ v[0] ] = v[1]; a }
					@response.body = instance_exec( *values, &block )
				}
			end
		end
		def forward path='/', target, &block
			any path+'*' do
				pi_prev = @request.path_info
				@request.path_info = @request.path_info[path.length .. pi_prev.length]
				target.call_with_scope( self )
				@request.path_info = pi_prev
			end
		end
		def conditions? scope, cond = {}
			-> c, m {
				c.nil? || ( c.is_a?(Array) ? c.include?(m) : c == m )
			}[ cond[:method], scope.request.request_method ]
		end
		def call env
			call_with_scope (s = Scope.new( env ))
			s.response.finish
		end
		def call_with_scope scope
			-> {
				not @mapper.each_pair { |k,p|
					return true if -> match {
						match && -> v {
							v && scope.instance_exec( v[:argnames], match.captures, &v[:block] )
							not v.nil?
						}[ p[:variants].select { |v| conditions?( scope, v[:conditions] ) && v[:block] }.first ]
					}[ p[:re].match( scope.request.path_info ) ]
				}
			}[] || -> r { r.status, r.body = 404, ['not found'] }[ scope.response ]
		end
	end
end


