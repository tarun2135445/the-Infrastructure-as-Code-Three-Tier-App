# Cost estimate

Order-of-magnitude monthly cost in `us-east-1`, with the default variables and **excluding free-tier credits**. Real spend depends on traffic and how long the stack is up — destroy when not in use.

| Resource                              | Monthly (USD) | Note                                              |
| ------------------------------------- | -------------:| ------------------------------------------------- |
| Application Load Balancer             | ~$16 + LCU    | Idle is fine; LCU adds with traffic.              |
| NAT Gateway (single)                  | ~$32 + data   | Doubles if `single_nat_gateway = false`.          |
| 2× t3.micro EC2                       | ~$15          | Free tier covers 750 hr/mo of one t2/t3.micro.    |
| RDS db.t3.micro Multi-AZ              | ~$30          | ~$15 single-AZ.                                   |
| RDS storage 20 GB gp3                 | ~$3           | Backups extra after 100% of allocated storage.    |
| Secrets Manager (1 secret)            | ~$0.40        | Plus $0.05 per 10k API calls.                     |
| CloudWatch alarms (4)                 | ~$0.40        |                                                   |
| Performance Insights (free tier)      | $0            | 7-day retention is free on db.t3.*.               |
| S3 + DynamoDB tfstate                 | < $1          | Pennies of storage, on-demand DynamoDB.           |
| Data transfer (light)                 | varies        |                                                   |
| **Estimated total, idle**             | **~$95-105**  | Tear down when you're done for the day.           |

## How to keep the bill near zero

- Run `make destroy` whenever you're not actively demoing.
- Keep `db_multi_az = false` in dev — saves ~$15/month.
- Keep `single_nat_gateway = true` in dev — saves ~$32/month.
- The state backend (S3 bucket + DynamoDB) is cheap; leave it up.

## What gets left behind by `terraform destroy`

By design, the bootstrap stack uses `prevent_destroy = true` on the state bucket so a stray `terraform destroy` can't nuke your remote state. To fully clean up:

```bash
make destroy                          # tears down infra/
cd bootstrap
aws s3 rm s3://<bucket>/ --recursive
aws s3 rb s3://<bucket>
# then remove the prevent_destroy lifecycle and `terraform destroy`,
# or just `aws dynamodb delete-table --table-name aws-portfolio-tfstate-locks`
```
