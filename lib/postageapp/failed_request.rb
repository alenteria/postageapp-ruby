module PostageApp::FailedRequest
  # == Module Methods =======================================================
  
  # Stores request object into a file for future re-send
  # returns true if stored, false if not (due to undefined project path)
  def self.store(request)
    return false unless (self.store_path) 
    return false unless (PostageApp.configuration.requests_to_resend.member?(request.method.to_s))
    
    unless (File.exist?(file_path(request.uid)))
      open(file_path(request.uid), 'wb') do |f|
        f.write(Marshal.dump(request))
      end
    end
    
    PostageApp.logger.info("STORING FAILED REQUEST [#{request.uid}]")
    
    true
  end

  def self.force_delete!(path)
    File.delete(path)

  rescue
    nil
  end
  
  # Attempting to resend failed requests
  def self.resend_all
    return false if !store_path
    Dir.foreach(store_path) do |filename|
      next if !filename.match /^\w{40}$/

      request = initialize_request(filename)

      next if reached_max_retries?(request)

      receipt_response = PostageApp::Request.new(:get_message_receipt, :uid => filename).send(true)
      log_retries(request)

      if receipt_response.fail?
        return
      elsif receipt_response.ok?
        PostageApp.logger.info "NOT RESENDING FAILED REQUEST [#{filename}]"
        File.delete(file_path(filename)) rescue nil

      elsif receipt_response.not_found? && !reached_max_retries?(request)
        PostageApp.logger.info "RESENDING FAILED REQUEST [#{filename}]"
        response = request.send(true)
        log_retries(request)
        # Not a fail, so we can remove this file, if it was then
        # there will be another attempt to resend
        File.delete(file_path(filename)) rescue nil if !response.fail?
      else
        PostageApp.logger.info "NOT RESENDING FAILED REQUEST [#{filename}], RECEIPT CANNOT BE PROCESSED"
        File.delete(file_path(filename)) rescue nil
      end
    end
    return
  end

  def self.reached_max_retries?(request)
    retries[request.uid].to_i >= PostageApp.config.max_retry
  rescue
    false
  end

  def self.log_retries(request)
    _retries = retries
    _retries[request.uid] = _retries[request.uid].to_i + 1
    File.open(retries_log_file, 'w+') do |f|
      f.write _retries.to_yaml
    end
  end

  def self.retries
    YAML.load_file(retries_log_file)
  rescue
    {}
  end

  def self.retries_log_file
    FileUtils.mkdir_p(File.join(File.expand_path(PostageApp.configuration.project_root), 'tmp'))
    File.join(File.join(PostageApp.configuration.project_root, "tmp/postageapp_retries.yaml"))
  end
  
  # Initializing PostageApp::Request object from the file
  def self.initialize_request(uid)
    return false unless (self.store_path)
    return false unless (File.exist?(file_path(uid)))

    Marshal.load(File.read(file_path(uid))) 

  rescue
    force_delete!(file_path(uid))

    false
  end
  
protected
  def self.store_path
    return unless (PostageApp.configuration.project_root)

    dir = File.join(
      File.expand_path(PostageApp.configuration.project_root),
      'tmp/postageapp_failed_requests'
    )
    
    unless (File.exist?(dir))
      FileUtils.mkdir_p(dir)
    end
    
    dir
  end
  
  def self.file_path(uid)
    File.join(store_path, uid)
  end
end
