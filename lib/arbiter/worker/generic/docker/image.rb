module DTK::Arbiter
  module Worker::Generic::Docker
    module Image

      DOCKER_TIMEOUT = 300

      def self.build(dockerfile, docker_image_tag)
        Docker.options[:read_timeout] = DOCKER_TIMEOUT
        Docker.options[:write_timeout] = DOCKER_TIMEOUT
        docker_image = ::Docker::Image.build(dockerfile)
        docker_image.tag('repo' => docker_image_tag, 'force' => true)
        docker_image
      end
    end
  end
end
