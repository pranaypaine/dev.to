class ProcessSizing
  def self.rss_size
    proc_file = "/proc/#{Process.pid}/status"
    proc_status = File.open(proc_file, "r") { |f| f.read_nonblock(4096).strip }
    /VmRSS:\s*(\d+) kB/.match(proc_status) { |match| match[1].to_f * 1024.0 }
  rescue StandardError
    -1
  end
end
