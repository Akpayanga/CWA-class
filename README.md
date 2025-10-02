# Cloud Cost Tracker & Alert System

## What This Project Does
This project is for tracking AWS costs. It uses Terraform to make everything. When costs go over the limit, SNS sends an email alert. Lambda gets the cost data from CloudWatch. EventBridge triggers Lambda every day. The data goes to DynamoDB to save it. It also goes to S3 for storage. CloudFront makes it fast to see on the webpage.

## How the Architecture Works (Flow from Diagram)
![Architecturea Diagram](https://github.com/user-attachments/assets/c0db03e6-1385-4e36-aaa6-1000c9322a5c)

This diagram illustrates the flow of data for a cost-monitoring system.

The process begins in the AWS Cloud (us-east-1 region). Inside a Virtual Private Cloud (VPC), Amazon CloudWatch monitors the billing metrics. If it detects that costs are too high, it sends an alert to Amazon SNS, which then forwards an email notification.

A separate, scheduled process uses Amazon EventBridge to trigger a Lambda function once every day. This Lambda function collects the detailed cost data from CloudWatch and stores it in a DynamoDB table named CostLogs, using a Timestamp as the primary key.

For the user-facing webpage, Amazon API Gateway provides an endpoint. When a user visits the page, it calls a Lambda function through this API. The Lambda function then retrieves the stored cost logs from the DynamoDB table and sends the list back.

The webpage itself is a simple HTML file (index.html) stored in an Amazon S3 bucket. Amazon CloudFront, a content delivery network, serves this file from S3 to users quickly and reliably. When the page loads in a user's browser, it fetches the cost log data from the API Gateway endpoint.

In summary, the entire system works like this: CloudWatch monitors the costs, Lambda logs the data to DynamoDB, SNS sends alerts, and the webpage, hosted on S3 and delivered by CloudFront, displays the information.

Looking at the Diagram:

The purple VPC section contains SNS, CloudWatch, EventBridge, Lambda, and DynamoDB. Outside the VPC, the API Gateway communicates with Lambda to fetch data, while S3 and CloudFront work together to deliver the webpage to the user.

![Architecturea Diagram](https://github.com/user-attachments/assets/c0db03e6-1385-4e36-aaa6-1000c9322a5c)

## How to Set Up
1. Get Terraform and AWS CLI.
2. Run `aws configure` with your key, secret, region us-east-1.
3. Make lambda folder with cost_tracker.py inside.
4. Make frontend folder with index.html inside.
5. Edit variables.tf for your email.

6. Run:
   - `terraform init` (gets AWS stuff).
   - `terraform plan` (shows what it will do).
   - `terraform apply` (type yes, wait 5-10 min).

7. Get links:
   - `terraform output dashboard_url` ([webpage link](https://d27h70zyrrzej8.cloudfront.net/)).
   - `terraform output api_endpoint` ([API link for data](https://6xi3acwttj.execute-api.us-east-1.amazonaws.com/prod/cost)).

## How to Test
1. AWS Console > Lambda > CostTracker > Test with {} empty > Invoke. This adds a log.
2. Open webpage link > Click Refresh Logs. See the costs.
3. Change threshold to 0.01 in variables.tf > apply > Run Lambda > Check email for alert.
4. To remove: `terraform destroy` (type yes).

## Challenges I Faced and How I Fixed Them
I had some problems, but fixed them one by one.

First, the webpage showed "Error loading logs". The browser blocked the fetch to API Gateway because of CORS. CORS is a rule that says only same site can get data. The diagram has CloudFront (webpage) and API Gateway (data) as different, so it blocked. I added OPTIONS method in API Gateway. This is like a pre-check. I set headers like Access-Control-Allow-Origin to *. Also, I had two deployment blocks in main.tf, which made error. I deleted the extra one and kept the one with depends_on for OPTIONS. After apply, the CORS went away, and logs loaded.

Second, Lambda could not get cost data from CloudWatch. It gave AccessDeniedException. The role lambda_exec_role did not have permission for ce:GetCostAndUsage. I added AWSBillingReadOnlyAccess policy to the role in Terraform. Also, I needed to enable Cost Explorer in Billing console. It took 24 hours for data, but for test, I ran Lambda a few times. Now it logs $0 or real costs.

Third, the API response was wrapped in "body": "[array]". The JS in HTML expected direct array, so map failed. I changed the script to JSON.parse(data.body || '[]'). This pulls the array out. Also, for the GET in Lambda, I added headers for CORS in case.

Fourth, S3 made the HTML download instead of show. Browser thought it was not HTML. I added content_type = "text/html" in the S3 object in Terraform. Now it renders the page with header, logs box, button, and footer.

Fifth, the footer was cut off in screenshot. I added width: 100% in style. Small thing, but looks better.

These fixes made it work end to end.

## What I Learned
Terraform is easy for big setups. One file does VPC, Lambda, all. IAM roles are important, you have to add policies for each service. CORS is annoying but OPTIONS fixes it. Debug with browser console and Lambda logs. For costs, enable Cost Explorer first.

## Files
- main.tf: All Terraform setup.
- variables.tf: Email and threshold.
- outputs.tf: Links.
- lambda/cost_tracker.py: Code for get and put costs.
- frontend/index.html: Webpage with script.
- screenshots:
    - Terraform output:
          <img width="1912" height="970" alt="Screenshot 2025-10-02 092607" src="https://github.com/user-attachments/assets/8b02fe03-32d6-43bd-962e-b7d4e11de7e6" />
    - CloudWatch:
          <img width="1898" height="947" alt="Screenshot 2025-10-02 090236" src="https://github.com/user-attachments/assets/d745d161-d556-45d4-b6c5-670d1ae3a68a" />
    - DynamoDB:
          <img width="1912" height="789" alt="Screenshot 2025-10-02 084153" src="https://github.com/user-attachments/assets/454e28af-84b0-4339-8aea-b4d4b841cf03" />
    - Dashboard (index.html):
          <img width="1897" height="1025" alt="Screenshot 2025-10-02 073610" src="https://github.com/user-attachments/assets/08e436ae-06c0-49fa-8b6e-a65a22b950b0" />

## Links Example
- Webpage: https://d27h70zyrrzej8.cloudfront.net
- API: https://6xi3acwttj.execute-api.us-east-1.amazonaws.com/prod/cost

## LinkedIn Post
[Link: https://www.linkedin.com/posts/your-post]

Thanks.
