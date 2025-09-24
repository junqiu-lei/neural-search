"""
TorchServe Handler for Agentic Search Model
Simple test handler for verifying multi-model deployment
"""

import json
import logging
import torch
from typing import List, Dict, Any

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Global variables
model_initialized = False
device = None


def handle(data, context):
    """
    TorchServe handler function for agentic search
    This is a simplified test handler that returns mock results
    """
    global model_initialized, device

    # Handle initialization call
    if data is None:
        data = []

    # Initialize on first call
    if not model_initialized:
        properties = context.system_properties if hasattr(context, 'system_properties') else {}
        device = torch.device("cuda:" + str(properties.get("gpu_id"))
                              if torch.cuda.is_available() and properties.get("gpu_id") is not None
                              else "cpu")

        logger.info(f"Agentic Search model initialized on {device}")
        model_initialized = True

    # Process requests
    results = []

    # Log raw data for debugging
    logger.info(f"Agentic Search - Raw data received: type={type(data)}, len={len(data) if data else 0}")

    for row in data:
        input_data = row.get("data") or row.get("body")
        if isinstance(input_data, str):
            try:
                input_data = json.loads(input_data)
            except:
                logger.error(f"Failed to parse input data: {input_data}")
                results.append({"error": "Invalid JSON input"})
                continue

        # Log the input for debugging
        logger.info(f"Agentic Search - Processing input_data type: {type(input_data)}")

        # Handle batch format (with 'inputs' field)
        if "inputs" in input_data and input_data["inputs"] is not None:
            inputs = input_data["inputs"]

            # Handle case where inputs might be a JSON string
            if isinstance(inputs, str):
                try:
                    inputs = json.loads(inputs)
                except:
                    logger.error(f"Failed to parse inputs string: {inputs}")
                    results.append({"error": "Invalid inputs format"})
                    continue

            if isinstance(inputs, list) and len(inputs) > 0:
                logger.info(f"Agentic Search - Processing batch with {len(inputs)} documents")
                # Return mock results for batch
                batch_results = []
                for i, item in enumerate(inputs):
                    mock_result = {
                        "agent_response": f"Mock agentic search result for document {i+1}",
                        "query": item.get("question", ""),
                        "confidence": 0.85,
                        "model": "agentic_search_test"
                    }
                    batch_results.append(mock_result)
                results.append({"results": batch_results})
            else:
                logger.error(f"Invalid inputs format: {inputs}")
                results.append({"error": "Invalid inputs format"})

        # Handle single format (direct question/context)
        elif "question" in input_data:
            logger.info("Agentic Search - Processing single document")
            # Return mock result for single query
            mock_result = {
                "agent_response": f"Mock agentic search result for: {input_data['question'][:50]}",
                "query": input_data["question"],
                "confidence": 0.85,
                "model": "agentic_search_test"
            }
            results.append(mock_result)
        else:
            logger.error(f"Invalid input format. Keys: {input_data.keys() if isinstance(input_data, dict) else 'not a dict'}")
            results.append({"error": "Invalid input format - expected 'question' or 'inputs' field"})

    logger.info(f"Agentic Search - Returning {len(results)} results")
    return results