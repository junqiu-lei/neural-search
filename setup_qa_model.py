#!/usr/bin/env python3

import requests
import json
import time
from datetime import datetime

def wait_for_task(base_url, task_id, max_retries=20):
    """Wait for a task to complete and return its status"""
    for i in range(max_retries):
        response = requests.get(f"{base_url}/_plugins/_ml/tasks/{task_id}")
        task_status = response.json()
        state = task_status.get("state")
        
        if state == "COMPLETED":
            return task_status
        elif state in ["FAILED", "ERROR"]:
            raise Exception(f"Task failed: {task_status}")
            
        print(f"Task state: {state}, waiting...")
        time.sleep(3)
    
    raise Exception("Timeout waiting for task completion")

def get_model_id(base_url, task_id):
    """Get model ID from task status or search"""
    task_status = wait_for_task(base_url, task_id)
    model_id = task_status.get("model_id")
    
    if not model_id:
        response = requests.get(f"{base_url}/_plugins/_ml/models/_search")
        models = response.json().get("hits", {}).get("hits", [])
        for model in models:
            if model.get("_source", {}).get("task_id") == task_id:
                model_id = model.get("_id")
                break
    
    if not model_id:
        raise Exception("Could not find model ID")
    
    return model_id

def setup_qa_model():
    base_url = "http://localhost:9200"
    
    # Generate timestamp for unique names
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    
    # Step 1: Enable ML on data nodes
    print("Enabling ML on data nodes...")
    settings_data = {
        "persistent": {
            "plugins.ml_commons.only_run_on_ml_node": False,
            "plugins.ml_commons.allow_registering_model_via_url": True
        }
    }
    response = requests.put(
        f"{base_url}/_cluster/settings",
        headers={"Content-Type": "application/json"},
        json=settings_data
    )
    print(f"Settings response: {response.json()}\n")

    # Step 2: Register model group
    print("Registering model group...")
    group_data = {
        "name": f"local_model_group_{timestamp}",
        "description": "A model group for local models"
    }
    response = requests.post(
        f"{base_url}/_plugins/_ml/model_groups/_register",
        headers={"Content-Type": "application/json"},
        json=group_data
    )
    group_response = response.json()
    model_group_id = group_response.get("model_group_id")
    print(f"Model Group ID: {model_group_id}\n")

    # Step 3: Register model
    print("Registering QA model...")
    model_data = {
        "name": f"test_question_answering_{timestamp}",
        "version": "1.0.0",
        "function_name": "QUESTION_ANSWERING",
        "description": "test model",
        "model_format": "TORCH_SCRIPT",
        "model_group_id": model_group_id,
        "model_content_hash_value": "f575403566bdd56d4f992632fccd5522512b49689e749d76fdd825394a851b2c",
        "model_config": {
            "model_type": "multi_span_qa",
            "framework_type": "huggingface_transformers"
        },
        "url": "https://github.com/junqiu-lei/ml-commons/releases/download/test17/opensearch_model_5.zip"
    }
    
    response = requests.post(
        f"{base_url}/_plugins/_ml/models/_register",
        headers={"Content-Type": "application/json"},
        json=model_data
    )
    
    # Add detailed error handling
    if response.status_code != 200:
        print(f"Error registering model. Status code: {response.status_code}")
        print(f"Response: {response.text}")
        raise Exception("Model registration failed")
        
    register_response = response.json()
    print(f"Register response: {json.dumps(register_response, indent=2)}\n")
    
    task_id = register_response.get("task_id")
    if not task_id:
        print("No task_id in response. Full response:")
        print(json.dumps(register_response, indent=2))
        raise Exception("No task_id returned from model registration")
        
    print(f"Task ID: {task_id}\n")

    # Step 4: Wait for registration and get model ID
    print("Waiting for registration to complete...")
    model_id = get_model_id(base_url, task_id)
    print(f"Model ID: {model_id}\n")

    # Step 5: Deploy model
    print("Deploying model...")
    response = requests.post(
        f"{base_url}/_plugins/_ml/models/{model_id}/_deploy",
        headers={"Content-Type": "application/json"}
    )
    deploy_response = response.json()
    
    # Wait for deployment to complete
    if "task_id" in deploy_response:
        deploy_task_id = deploy_response.get("task_id")
        print(f"Waiting for deployment task {deploy_task_id} to complete...")
        wait_for_task(base_url, deploy_task_id)
    
    print(f"Deploy response: {deploy_response}\n")
    return model_id

if __name__ == "__main__":
    try:
        model_id = setup_qa_model()
        print(f"Setup completed successfully. Model ID: {model_id}")
    except Exception as e:
        print(f"Error during setup: {str(e)}") 