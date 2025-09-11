#!/usr/bin/env python3
"""
Test script for the TorchServe handler
Tests both single document and batch processing formats
"""

import json
import requests
import sys

TORCHSERVE_URL = "http://localhost:8080/predictions/semantic_highlighter"

def test_single_document():
    """Test single document format"""
    print("Testing single document format...")
    
    payload = {
        "question": "What is OpenSearch?",
        "context": "OpenSearch is a search engine that helps you find information."
    }
    
    response = requests.post(TORCHSERVE_URL, json=payload)
    
    if response.status_code == 200:
        result = response.json()
        print(f"✓ Single document test passed")
        print(f"  Response: {json.dumps(result, indent=2)}")
        
        # Verify format
        assert "highlights" in result
        assert isinstance(result["highlights"], list)
        for highlight in result["highlights"]:
            assert "start" in highlight
            assert "end" in highlight
        return True
    else:
        print(f"✗ Single document test failed: {response.status_code}")
        print(f"  Response: {response.text}")
        return False


def test_batch_processing():
    """Test batch processing format"""
    print("\nTesting batch processing format...")
    
    payload = {
        "inputs": [
            {
                "question": "What is OpenSearch?",
                "context": "OpenSearch is a search engine."
            },
            {
                "question": "What is OpenSearch?",
                "context": "It helps you find information quickly."
            }
        ]
    }
    
    response = requests.post(TORCHSERVE_URL, json=payload)
    
    if response.status_code == 200:
        result = response.json()
        print(f"✓ Batch processing test passed")
        print(f"  Response: {json.dumps(result, indent=2)}")
        
        # Verify format
        assert "highlights" in result
        assert isinstance(result["highlights"], list)
        assert len(result["highlights"]) == 2  # Should have 2 results
        
        for doc_highlights in result["highlights"]:
            assert isinstance(doc_highlights, list)
            for highlight in doc_highlights:
                assert "start" in highlight
                assert "end" in highlight
        return True
    else:
        print(f"✗ Batch processing test failed: {response.status_code}")
        print(f"  Response: {response.text}")
        return False


def main():
    """Run all tests"""
    print("=" * 60)
    print("TorchServe Handler Test Suite")
    print("=" * 60)
    
    try:
        # Check if TorchServe is running
        response = requests.get("http://localhost:8080/ping")
        if response.status_code != 200:
            print("ERROR: TorchServe is not running")
            sys.exit(1)
            
        # Check if model is loaded
        response = requests.get("http://localhost:8081/models")
        models = response.json()
        if not any(m.get("modelName") == "semantic_highlighter" for m in models.get("models", [])):
            print("ERROR: semantic_highlighter model is not loaded")
            sys.exit(1)
            
        print("✓ TorchServe is running and model is loaded\n")
        
        # Run tests
        tests_passed = []
        tests_passed.append(test_single_document())
        tests_passed.append(test_batch_processing())
        
        # Summary
        print("\n" + "=" * 60)
        print("Test Summary")
        print("=" * 60)
        passed = sum(tests_passed)
        total = len(tests_passed)
        print(f"Passed: {passed}/{total}")
        
        if all(tests_passed):
            print("✓ All tests passed!")
            sys.exit(0)
        else:
            print("✗ Some tests failed")
            sys.exit(1)
            
    except requests.exceptions.ConnectionError:
        print("ERROR: Cannot connect to TorchServe at localhost:8080")
        print("Make sure TorchServe is running")
        sys.exit(1)
    except Exception as e:
        print(f"ERROR: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()