namespace :routes do
  desc "Rebuild db/routes/routes.json: real bus routes between every pair of preset places. " \
       "Uses ROUTING_PROVIDERS (default vegvesen,osrm). Only missing pairs unless ALL=1. THREADS=4 for parallel requests."
  task refresh: :environment do
    r = Pricing::Routing
    out = r.table.dup
    todo = Pricing::CITIES.keys.combination(2).map(&:sort)
    todo.reject! { |x, y| out[r.key(x, y)] } unless ENV["ALL"] == "1"
    total = todo.size
    queue = Queue.new
    todo.each { |pair| queue << pair }
    lock = Mutex.new
    done = 0
    save = -> { r::TABLE_PATH.write(JSON.pretty_generate(out.sort.to_h) + "\n") }
    # Vegvesen allows 2 500 requests a day; the public OSRM demo only 1 per second, so keep THREADS=1 for OSRM
    workers = Array.new(ENV.fetch("THREADS", "1").to_i.clamp(1, 8)) do
      Thread.new do
        while (pair = (queue.pop(true) rescue nil))
          from, to = pair
          row = r.fetch(Pricing::Places.resolve(from), Pricing::Places.resolve(to))
          lock.synchronize do
            done += 1
            k = r.key(from, to)
            if row
              out[k] = row
              $stdout.puts format("%3d/%d %-45s %6.1f km %5.2f h toll %4s %-8s %s", done, total, k, row["km"], row["h"],
                                  row["toll"] || "-", row["src"], row["ferries"].join(", "))
            else
              warn "#{k}: no route (kept estimate)"
            end
            $stdout.flush
            save.() if (done % 25).zero?
          end
          sleep 1.0
        end
      end
    end
    workers.each(&:join)
    save.()
    puts "Wrote #{out.size} routes to #{r::TABLE_PATH}"
  end
end
