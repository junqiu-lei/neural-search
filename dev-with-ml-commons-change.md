Neural Search with ml-commons changes dev

This guide provides step-by-step instructions for developing the neural-search plugin with custom ml-commons change with 3.1.0 version as example.

Step 1: Build ML-Commons Changes

1. Navigate to the ml-commons directory:

cd /path/to/ml-commons

2. Build ml-commons with your changes:

bash ./scripts/build.sh -v 3.1.0 -s true

This will create the necessary artifacts in the `artifacts/plugins` directory.


Step 2: Update Neural Search Plugin Dependencies

1. Navigate to the neural-search plugin directory:

cd /path/to/neural-search

2. Update the build.gradle file with the following dependencies:

gradle
dependencies {
    // ML Plugin
    zipArchive files("/path/to/ml-commons/artifacts/plugins/opensearch-ml-3.1.0.0-SNAPSHOT.zip")
    
    // ML Client and Common JARs
    api files("/path/to/ml-commons/client/build/libs/opensearch-ml-client-3.1.0.0-SNAPSHOT.jar")
    api files('/path/to/ml-commons/build/libs/opensearch-ml-3.1.0.0-SNAPSHOT.jar')
    api files('/path/to/ml-commons/common/build/distributions/opensearch-ml-common-3.1.0.0-SNAPSHOT.jar')
}


Step 3: Configure Plugin Installation Order

Ensure the following configuration is in your `build.gradle` to handle plugin dependencies correctly:

testClusters.integTest {
    testDistribution = "ARCHIVE"

    // Install plugins in the correct order
    // First install job-scheduler plugin
    configurations.zipArchive.asFileTree.each {
        if (it.name.contains("opensearch-job-scheduler")) {
            plugin(provider(new Callable<RegularFile>(){
                @Override
                RegularFile call() throws Exception {
                    return new RegularFile() {
                        @Override
                        File getAsFile() {
                            return it
                        }
                    }
                }
            }))
        }
    }

    // Then install K-NN plugin
    configurations.zipArchive.asFileTree.each {
        if (it.name.contains("opensearch-knn")) {
            plugin(provider(new Callable<RegularFile>(){
                @Override
                RegularFile call() throws Exception {
                    return new RegularFile() {
                        @Override
                        File getAsFile() {
                            return it
                        }
                    }
                }
            }))
        }
    }

    // Finally install ml plugin
    configurations.zipArchive.asFileTree.each {
        if (it.name.contains("opensearch-ml")) {
            plugin(provider(new Callable<RegularFile>(){
                @Override
                RegularFile call() throws Exception {
                    return new RegularFile() {
                        @Override
                        File getAsFile() {
                            return it
                        }
                    }
                }
            }))
        }
    }

    // Install neural-search plugin
    plugin(project.tasks.bundlePlugin.archiveFile)
}



Step 4: Build and Run

Run the plugin:

./gradlew run

