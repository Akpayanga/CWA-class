import boto3
import json
import datetime
import os  # Add this import for os.environ

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['DYNAMODB_TABLE'])  # Use env var for table name

def lambda_handler(event, context):
    # If it's an API GET request (has 'httpMethod': 'GET'), read logs
    if 'httpMethod' in event and event['httpMethod'] == 'GET':
        response = table.scan(Limit=10)  # Get last 10 logs
        logs = response['Items']
        # Format for frontend: map to {message, id}
        formatted_logs = [
            {
                'message': f"Estimated cost: ${item.get('Cost', 'N/A')}",
                'id': item['Timestamp']
            }
            for item in logs
        ]
        return {
    'statusCode': 200,
    'headers': {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type'
    },
    'body': json.dumps(formatted_logs)  # Return as array
}

    # Default: Write a log (for scheduled EventBridge trigger)
    else:
        client = boto3.client('ce')
        response = client.get_cost_and_usage(
            TimePeriod={
                'Start': (datetime.datetime.now() - datetime.timedelta(days=1)).strftime('%Y-%m-%d'),
                'End': datetime.datetime.now().strftime('%Y-%m-%d')
            },
            Granularity='DAILY',
            Metrics=['UnblendedCost']
        )
        
        cost = response['ResultsByTime'][0]['Total']['UnblendedCost']['Amount'] if response['ResultsByTime'] else '0.00'
        table.put_item(Item={
            'Timestamp': datetime.datetime.now().isoformat(),
            'Cost': cost
        })
        
        return {
            'statusCode': 200,
            'body': json.dumps('Cost logged successfully')
        }
