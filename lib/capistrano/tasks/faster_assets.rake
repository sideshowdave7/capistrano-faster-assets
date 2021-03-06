# Original source: https://coderwall.com/p/aridag


# set the locations that we will look for changed assets to determine whether to precompile
set :assets_dependencies, %w(app/assets lib/assets vendor/assets Gemfile.lock config/routes.rb yarn.lock app/javascript)

class PrecompileRequired < StandardError;
end

namespace :deploy do
  namespace :assets do
    desc "Precompile assets"
    task :precompile do
      on roles(fetch(:asset_precompiler)) do
        within release_path do
          with rails_env: fetch(:rails_env) do
            begin
              # find the most recent release
              latest_release = capture(:ls, '-xr', releases_path).split[1]

              # precompile if this is the first deploy
              raise PrecompileRequired unless latest_release

              latest_release_path = releases_path.join(latest_release)

              # precompile if the previous deploy failed to finish precompiling
              execute(:ls, latest_release_path.join('assets_manifest_backup')) rescue raise(PrecompileRequired)

              fetch(:assets_dependencies).each do |dep|
                release = release_path.join(dep)
                latest = latest_release_path.join(dep)

                # skip if both directories/files do not exist
                next if [release, latest].map{|d| test "[ -e #{d} ]"}.uniq == [false]

                # execute raises if there is a diff
                execute(:diff, '-Nqr', release, latest) rescue raise(PrecompileRequired)
              end

              info("Skipping asset precompile, no asset diff found")

              # copy over all of the assets from the last release
              release_asset_path = release_path.join('public', fetch(:assets_prefix))
              # skip if assets directory is symlink
              begin
                execute(:test, '-L', release_asset_path.to_s)
              rescue
                execute(:cp, '-r', latest_release_path.join('public', fetch(:assets_prefix)), release_asset_path.parent)
              end

              # Webpacker assets
              # copy over all of the assets from the last release
              release_asset_path = release_path.join('public/packs')
              # skip if assets directory is symlink
              begin
                execute(:test, '-L', release_asset_path.to_s)
              rescue
                execute(:cp, '-r', latest_release_path.join('public/packs'), release_asset_path.parent)
              end

              # check that the manifest has been created correctly, if not
              # trigger a precompile
              begin
                # Support sprockets 2
                execute(:ls, release_asset_path.join('manifest*'))
              rescue
                begin
                  # Support sprockets 3
                  execute(:ls, release_asset_path.join('.sprockets-manifest*'))
                rescue
                  raise(PrecompileRequired)
                end
              end

            rescue PrecompileRequired
              execute "mkdir -p #{shared_path}/assets && ln -nfs #{shared_path}/public/assets #{release_path}/public/assets"
              execute "cd #{release_path} && RAILS_ENV=#{fetch(:rails_env)} RAILS_GROUPS=assets bundle exec rake assets:precompile --trace"
            end
          end
        end
      end
    end
  end
end
