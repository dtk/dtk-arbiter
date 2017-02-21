module DTK::Arbiter
  module Worker::Generic::Docker
    module Image
      def self.build(dockerfile, docker_image_tag)
        docker_image = ::Docker::Image.build(dockerfile)
        docker_image.tag('repo' => docker_image_tag, 'force' => true)
        docker_image
      end
    end
  end
end
