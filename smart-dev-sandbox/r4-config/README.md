
# a server specific change needs to be made after copying this application.yaml to the ~/git/smart-dev-sandbox docker repo #
# server_address must be set to the hostname.  
# there is a docker setting that will eliminate this need but it has not been tested yet.

  # -------------------------------------------------------------------------------
  # S. Testers (webui)
  # -------------------------------------------------------------------------------
    tester:
      home:
        name: Local Tester
        server_address: 'http://smart-fhir.immunization-registries.org:4004/fhir'
        refuse_to_fetch_third_party_urls: false
        fhir_version: R4

