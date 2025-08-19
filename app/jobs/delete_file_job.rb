class DeleteFileJob < ApplicationJob
  queue_as :low
  retry_on StandardError, wait: :polynomially_longer, attempts: 3
  
  def perform(file_path)
    Rails.logger.info "Attempting to delete file: #{file_path}"
    
    unless file_path.present?
      Rails.logger.warn "DeleteFileJob called with empty file_path"
      return
    end
    
    # Security check: ensure file is in tmp directory
    unless file_path.start_with?(Rails.root.join('tmp').to_s)
      Rails.logger.error "Security violation: Attempted to delete file outside tmp directory: #{file_path}"
      raise SecurityError, "File path not in temporary directory"
    end
    
    if File.exist?(file_path)
      begin
        File.delete(file_path)
        Rails.logger.info "Successfully deleted temporary file: #{file_path}"
      rescue Errno::ENOENT
        Rails.logger.info "File already deleted: #{file_path}"
      rescue Errno::EACCES => e
        Rails.logger.error "Permission denied deleting file #{file_path}: #{e.message}"
        raise
      rescue StandardError => e
        Rails.logger.error "Unexpected error deleting file #{file_path}: #{e.message}"
        raise
      end
    else
      Rails.logger.info "File not found (may have been already deleted): #{file_path}"
    end
  rescue SecurityError => e
    Rails.logger.error "Security error in DeleteFileJob: #{e.message}"
    raise
  rescue StandardError => e
    Rails.logger.error "DeleteFileJob failed for file #{file_path}: #{e.message}"
    raise
  end
end