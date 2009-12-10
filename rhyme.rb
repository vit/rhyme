%w[rack].each {|r| require r}

module Rhyme
	class Scope
		attr_accessor :request, :response
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
			super
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
					'(\w+)'
				end
			}
			@mapper[path] ||= {re: Regexp.new( ?^ + path + ?$ ), variants: [] }
			@mapper[path][:variants] << {conditions: {}.merge(cond), argnames: names, block: block}
		end
		alias_method :any, :add_path
		{get: ['GET', 'HEAD'], head: 'HEAD', post: 'POST', put: 'PUT', delete: 'DELETE'}.each_pair do |reqmethod, conditions|
			define_method reqmethod do | path='/', cond={}, &block |
				any path, cond.merge( {method: conditions} ), &block
			end
		end
		def forward path='/', target, &block
			any path+'*' do
				pi_prev = @request.path_info
				@request.path_info = @request.path_info[path.length..pi_prev.length]
				result = target.call_ext(self)
				@request.path_info = pi_prev
				result
			end
		end
		def conditions? scope, cond = {}
			-> c, m {
				c.nil? || ( c.is_a?(Array) ? c.include?(m) : c == m )
			}[ cond[:method], scope.request.request_method ]
		end
		def call env
			s = Scope.new
			s.request = Request.new env
			s.response = Rack::Response.new
			call_ext s
			s.response.finish
		end
		def call_ext scope
			blk = nil
			@mapper.each_pair { |k,p|
				if match = p[:re].match(scope.request.path_info)
					values = match.captures
					p[:variants].each { |v|
						if conditions? scope, v[:conditions]
							blk = v[:block]
							break
						end
					}
				end
			}
			if blk
				scope.response.body = scope.instance_eval &blk
			else
				scope.response.status = 404
				scope.response.body = 'not found'
			end
		end
	end
end


