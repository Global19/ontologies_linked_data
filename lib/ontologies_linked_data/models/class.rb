require "set"

module LinkedData
  module Models
    class ClassAttributeNotLoaded < StandardError
    end

    class Class

      attr_reader :resource_id
      attr_reader :attributes
      attr_reader :submission
      attr_accessor :loaded_labels

      def initialize(resource_id, submission, plabel = nil, synonyms = nil, definitions = nil)
        @resource_id = resource_id

        @attributes = {}

        if !plabel.nil?
          set_prefLabel plabel
        end
        @attributes[:synonyms] = synonyms
        @attributes[:definitions] = definitions

        #backreference to the submission that "owns" the term
        @submission = submission
        @loaded_attributes = false
        @loaded_labels = !plabel.nil?
      end

      private

      def set_prefLabel(label_input)
        label = nil
        if label_input.instance_of? Array
          return if label_input.length == 0
          if label_input.length > 1
            raise ArgumentError, "Class model only allows one label. TODO: internationalization"
          end
          if label_input.length == 1
            label = label_input[0]
          end
        else
          label = label_input
        end
        if label.instance_of? SparqlRd::Resultset::Literal
          @attributes[:prefLabel] = label
        else
          raise ArgumentError, "Unknown type of prefLabel #{label.class.name}"
        end
      end

      public

      def prefLabel
        raise ClassAttributeNotLoaded, "prefLabel attribute is not loaded" unless @loaded_labels
        return @attributes[:prefLabel]
      end

      def definitions
        raise ClassAttributeNotLoaded, "Definitions attribute is not loaded" unless @loaded_labels
        return @attributes[:definitions]
      end

      def synonymLabel
        raise ClassAttributeNotLoaded, "synonymLabel attribute is not loaded" unless @loaded_labels
        return @attributes[:synonyms]
      end

      def loaded_parents?
        return !@attributes[:parents].nil?
      end


      def loaded_children?
        return !@attributes[:children].nil?
      end

      def self.find(*args)
        raise ArgumentError,
          "Find is not supported in the Class model. Use .where (:submission => s, :resource_id => id)"
        #TODO eventually we can bypass this exception and call .where from here.
      end

      def loaded_labels?
        return @load_labels
      end

      def load_labels
        #Just get a copy of the same class with labels and copy the attributes
        classes = LinkedData::Models::Class.where(submission: @submission, resource_id: @resource_id)
        @attributes[:prefLabel] = classes[0].prefLabel
        @attributes[:synonyms] = classes[0].synonymLabel
        @attributes[:definitions] = classes[0].definitions
        @loaded_labels = true
        return self
      end

      def load_parents
        parents = load_relatives
        @attributes[:parents] = parents
        return parents
      end

      def load_children
        children = load_relatives(children=true)
        @attributes[:children]  = children
        return children
      end

      private
      def load_non_standard_attributes
        graph = submission.resource_id
        query = <<eos
SELECT DISTINCT ?predicate ?object WHERE {
  GRAPH <#{graph.value}> {
    <#{self.resource_id.value}> ?predicate ?object .
    FILTER (!isBLANK(?object))
} }
eos
        rs = Goo.store.query(query)

        #These predicates are considered standard.
        #We do not load them here
        standard_predicates = []
        standard_predicates << LinkedData::Utils::Namespaces.default_altLabel_iri.value
        standard_predicates << (@submission.hierarchyProperty ||
                                LinkedData::Utils::Namespaces.default_hieararchy_property_iri.value)
        standard_predicates << LinkedData::Utils::Namespaces.default_pref_label_iri.value
        standard_predicates << LinkedData::Utils::Namespaces.meta_prefLabel_iri.value
        standard_predicates << LinkedData::Utils::Namespaces.default_definition_iri.value
        standard_predicates << @submission.prefLabelProperty.value
        rs.each_solution do |sol|
          pred_value=sol.get(:predicate).value
          next if standard_predicates.include? pred_value
          (@attributes[pred_value] = []) unless (@attributes.include? pred_value)
          @attributes[pred_value] << sol.get(:object)
        end
      end

      def load_relatives(children=false)
        #by default loads parents
        hierarchyProperty = @submission.hierarchyProperty ||
                                LinkedData::Utils::Namespaces.default_hieararchy_property_iri
        graph = submission.resource_id
        if children
          relative_pattern = " ?relativeId <#{hierarchyProperty.value}> <#{self.resource_id.value}> . "
        else
          relative_pattern = " <#{self.resource_id.value}> <#{hierarchyProperty.value}> ?relativeId . "
        end
        query = <<eos
SELECT DISTINCT ?relativeId WHERE {
  GRAPH <#{graph.value}> {
    #{relative_pattern}
    FILTER (!isBLANK(?parentId))
} } ORDER BY ?relativeId
eos
        rs = Goo.store.query(query)
        relatives = []
        rs.each_solution do |sol|
          relatives << LinkedData::Models::Class.new(sol.get(:relativeId), self.submission)
        end
        return relatives
      end

      public
      def parents
        raise ClassAttributeNotLoaded, "Parents are not loaded. Call .load_parents" \
          unless self.loaded_parents?
        return @attributes[:parents]
      end

      def children
        raise ClassAttributeNotLoaded, "Children are not loaded. Call .load_children" \
          unless self.loaded_children?
        return @attributes[:children]
      end

      # true if all attributes have been loaded
      def loaded_attributes?
        return @load_attributes
      end

      def load_attributes
        load_parents unless loaded_parents?
        load_children unless loaded_children?
        load_non_standard_attributes
        @loaded_attributes = true
      end

      private
      def self.labels_query_block(generating_missing=false)
        syn_predicate = LinkedData::Utils::Namespaces.default_altLabel_iri
        if generating_missing
          syn_predicate = LinkedData::Utils::Namespaces.rdfs_label_iri
        end
        labels_block = <<eos
OPTIONAL { ?id <#{LinkedData::Utils::Namespaces.default_pref_label_iri.value}> ?prefLabel . }
OPTIONAL { ?id <#{syn_predicate.value}> ?synonymLabel . }
OPTIONAL { ?id <#{LinkedData::Utils::Namespaces.default_definition_iri.value}> ?definition . }
eos
        return labels_block
      end

      public
      def self.where(*args)
        params = args[0]
        submission = params[:submission]
        if submission.nil?
          raise ArgumentError, "Submission needs to be provided to retrieve terms"
        end

        load_labels = params.include?(:labels) ? params[:labels] : true
        graph = submission.resource_id
        submission.load if (!submission.nil? and !submission.loaded?)
        classType =  submission.classType || LinkedData::Utils::Namespaces.default_type_for_classes_iri

        one_class_filter = ""
        if params.include? :resource_id
          resource_id = params[:resource_id]
          raise ArgumentError, "Resource ID Class.where needs to be a RDF::IRI" \
            unless resource_id.kind_of? SparqlRd::Resultset::IRI
          one_class_filter = "FILTER (?id = <#{resource_id.value}>)"
        end

        root_class_filter = ""
        if params.include? :root and params[:root]
          #TODO: UMLS ontologies behave differently
          hierarchyProperty = submission.hierarchyProperty ||
                                  LinkedData::Utils::Namespaces.default_hieararchy_property_iri
          root_class_filter = <<eos
OPTIONAL { ?id <#{hierarchyProperty.value}> ?superId .}
FILTER(!bound(?superId))
eos
        end

        labels_block = ""
        query_options = {}
        if load_labels
          query_options[:rules] = :SUBP
          labels_block = labels_query_block(params.include? :missing_labels_generation)
        end

        query = <<eos
SELECT DISTINCT * WHERE {
  GRAPH <#{graph.value}> {
    ?id a <#{classType.value}> .
    #{labels_block}
    #{one_class_filter}
    #{root_class_filter}
    FILTER(!isBLANK(?id))
} } ORDER BY ?id
eos
        rs = Goo.store.query(query, query_options)
        classes = []
        prefLabel_set = nil
        synonyms_set = nil
        definitions_set = nil
        prev = nil
        rs.each_solution do |sol|
          if load_labels
            if !prev.nil? and prev.value != sol.get(:id).value
              classes << LinkedData::Models::Class.new(prev,
                                   submission,prefLabel_set.to_a,synonyms_set.to_a,definitions_set.to_a)
              prev = nil
            end
            if prev.nil?
              prefLabel_set = Set.new
              synonyms_set = Set.new
              definitions_set = Set.new
            end
            prefLabel_set << sol.get(:prefLabel) unless sol.get(:prefLabel).nil?
            synonyms_set << sol.get(:synonymLabel) unless sol.get(:synonymLabel).nil?
            definitions_set << sol.get(:definition) unless sol.get(:definition).nil?
            prev = sol.get(:id)
            next
          end
          #whitout labels
          classes <<  LinkedData::Models::Class.new(sol.get(:id), submission)
        end
        if load_labels and prev != nil
              classes <<  LinkedData::Models::Class.new(prev,submission,
                                    prefLabel_set.to_a,synonyms_set.to_a,definitions_set.to_a)
        end
        return classes
      end

    end
  end
end
