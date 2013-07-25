require_relative "../test_case"

class TestMetrics < LinkedData::TestCase

  def self.after_suite
    os = LinkedData::Models::Ontology.find("METRICS-TEST").first
    os.delete if os
  end

  def delete_submission
    os = LinkedData::Models::Ontology.find("METRICS-TEST").first
    os.delete if os
  end

  def create_submission
    acronym = "METRICS-TEST"
    name = "testing metrics"
    ontologyFile = "./test/data/ontology_files/BRO_v3.2.owl"
    id = 10

    owl, bogus, user, status, contact =
      submission_dependent_objects("OWL", acronym, "test_linked_models", "UPLOADED")
    os = LinkedData::Models::OntologySubmission.new
    os.submissionId = id
    os.contact = [contact]
    os.released = DateTime.now - 4
    bogus.name = name
    o = LinkedData::Models::Ontology.find(acronym)
    if o.nil?
      os.ontology = LinkedData::Models::Ontology.new(:acronym => acronym)
    else
      os.ontology = o
    end
    uploadFilePath = 
     LinkedData::Models::OntologySubmission.copy_file_repository(acronym, 
                                                                 id, 
                                                                 ontologyFile)
    os.uploadFilePath = uploadFilePath
    os.hasOntologyLanguage = owl
    os.ontology = bogus
    os.submissionStatus = status
    os.save
  end

  def test_metrics_creation
    create_submission
    os = LinkedData::Models::OntologySubmission
                      .where(ontology: [acronym: "METRICS-TEST"])
                      .include(LinkedData::Models::OntologySubmission.attributes)
                      .first

    metrics_id = RDF::URI.new(os.id.to_s + "/metrics")
    metrics = LinkedData::Models::Metrics.find(metrics_id).first
    if metrics
      metrics.delete
    end

    metrics = LinkedData::Models::Metrics.new
    metrics.id = metrics_id
    metrics.classes = 1
    metrics.individuals = 2
    metrics.properties = 3
    metrics.max_depth = 1
    metrics.max_children = 1
    metrics.classes_one_child= "aaaa"
    metrics.classes_with_no_definition = 1
    assert !metrics.valid?
    assert metrics.errors[:avg_children]
    assert metrics.errors[:classes_one_child]
    metrics.classes_one_child= 1
    metrics.classes_25_children = 1
    metrics.avg_children = 1
    assert metrics.valid?
    metrics.save

    #make the link with submission
    os.metrics = metrics
    os.save

    LinkedData::Models::OntologySubmission
                      .where.models([os])
                      .include(metrics: LinkedData::Models::Metrics.attributes)
                      .all

    assert_instance_of LinkedData::Models::Metrics, os.metrics
    metric_from_db = os.metrics
    assert metric_from_db.classes == 1
    assert metric_from_db.individuals == 2
    assert metric_from_db.properties == 3 
    assert metric_from_db.max_depth == 1

    metric_from_db.delete
    delete_submission
  end

end