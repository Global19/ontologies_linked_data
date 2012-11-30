module LinkedData
  module Models
    class User < Goo::Base::Resource
      model :user
      validates :username, :presence => true, :cardinality => { :maximum => 1 }
      unique :username

      def initialize(attributes = {})
        super(attributes)
      end
    end
  end
end