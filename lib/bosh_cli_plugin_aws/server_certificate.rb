require 'openssl'

module Bosh::Aws
  class ServerCertificate
    class SubjectsDoNotMatchException < RuntimeError; end

    def initialize(key_path, certificate_path, domain, dns_record, chain_path = nil)
      @key_path = key_path
      @certificate_path = certificate_path
      @chain_path = chain_path
      @subject_string = subject_string(domain, dns_record)
    end

    def load_or_create
      @key, @csr_cert = load_or_create_key_and_csr_cert
      @chain = OpenSSL::X509::Certificate.new(File.read(@chain_path)) if @chain_path

      self
    end

    def key
      @key.to_pem
    end

    def certificate
      @csr_cert.to_pem
    end

    def chain
      @chain.to_pem if @chain
    end

    private

    def load_or_create_key_and_csr_cert
      File.exists?(@key_path) ? load_key_and_csr_cert : create_key_and_csr_cert
    end

    def load_key_and_csr_cert
      key = OpenSSL::PKey::RSA.new(File.read(@key_path))
      csr_cert = OpenSSL::X509::Certificate.new(File.read(@certificate_path))
      subject = OpenSSL::X509::Name.parse(@subject_string)

      raise SubjectsDoNotMatchException.new(
        "The subject you provided is '#{subject}' but the certificate you loaded has a subject of '#{csr_cert.subject}'."
      ) unless csr_cert.subject == subject

      [key, csr_cert]
    end

    def create_key_and_csr_cert
      subject = OpenSSL::X509::Name.parse(@subject_string)
      key = OpenSSL::PKey::RSA.new(2048)
      csr = new_csr(key, subject)
      csr_cert = new_csr_certificate(key, csr)

      File.write(@key_path, key.to_pem)
      File.write(@certificate_path, csr_cert.to_pem)

      [key, csr_cert]
    end

    def new_csr(key, subject)
      csr = OpenSSL::X509::Request.new
      csr.version = 0
      csr.subject = subject
      csr.public_key = key.public_key
      csr.sign key, OpenSSL::Digest::SHA1.new

      csr
    end

    def new_csr_certificate(key, csr)
      csr_cert = OpenSSL::X509::Certificate.new
      csr_cert.serial = 0
      csr_cert.version = 2
      csr_cert.not_before = Time.now - 60 * 60 * 24
      csr_cert.not_after = Time.now + 94608000

      csr_cert.subject = csr.subject
      csr_cert.public_key = csr.public_key
      csr_cert.issuer = csr.subject

      csr_cert.sign key, OpenSSL::Digest::SHA1.new

      csr_cert
    end

    def subject_string(domain, dns_record)
      "/C=US/O=Pivotal/CN=#{dns_record}.#{domain}"
    end
  end
end


