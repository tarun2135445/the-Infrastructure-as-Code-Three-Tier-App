# Design decisions

Short, opinionated answers to "why is it built this way?" — the kind of thing an interviewer asks when they say "walk me through your architecture."

## Why three subnet tiers instead of two?

A two-tier (public + private) layout works, but it forces the DB security group to allow Postgres from the entire private CIDR — every private workload, not just the app. Splitting app and data into separate tiers lets the DB SG allow only the *app SG* on 5432. The blast radius if an app instance is compromised stays at the database tier; another workload sharing the VPC can't reach the DB at all.

## Why private subnets for the database?

RDS doesn't need inbound internet. Putting it in subnets with no IGW route eliminates an entire class of misconfiguration ("oops, the SG allows 0.0.0.0/0"). `publicly_accessible = false` is belt-and-braces — even if someone tried to assign a public IP, the route table couldn't reach the internet anyway.

## Why Multi-AZ on RDS?

Single-AZ RDS has a 30-90 minute recovery window if the AZ goes down. Multi-AZ has a synchronous standby in another AZ; failover is typically under 60 seconds and the connection endpoint never changes. It costs roughly 2× — worth it for any system you'd be embarrassed to lose for an hour.

## Why one NAT Gateway instead of two?

Cost. A NAT Gateway is roughly $32/month plus data. Two of them double that. For a learning/portfolio environment this isn't worth it. The trade-off is documented and toggleable: set `single_nat_gateway = false` and Terraform fans out one NAT per AZ with per-AZ route tables, so a single-AZ NAT outage doesn't take out egress for private subnets in the other AZ.

## Why SSM Session Manager and no bastion host?

A bastion is a 24/7 EC2 instance whose only job is to terminate SSH sessions, with key management to go with it. SSM gives you the same access via IAM, with full audit logging in CloudTrail, no public IP, no SSH keys, no key rotation, and zero idle cost. The agent ships in Amazon Linux 2023, so this is "free" once the instance role grants `AmazonSSMManagedInstanceCore`.

The subtle catch: SSM endpoints aren't in the VPC by default, so the agent reaches them via NAT. If you can't accept the cost of NAT during an AZ outage, add VPC interface endpoints for `ssm`, `ssmmessages`, and `ec2messages` (~$22/month/AZ).

## Why generate the DB password in Terraform vs. set it via tfvars?

A password in tfvars is a password on someone's laptop and in shell history. A `random_password` resource is generated at apply time, lives only in state (encrypted in S3), and gets handed straight to Secrets Manager. The application never sees the password as an environment variable; it pulls the secret at runtime via instance role.

## Why store creds in Secrets Manager and not SSM Parameter Store?

Both work. Secrets Manager wins on rotation (managed rotation lambdas for RDS), versioning, and resource-policy support. The cost is $0.40/secret/month — meaningless at this scale. For a single-secret learning project either is fine; Secrets Manager scales further.

## Why IMDSv2 required?

IMDSv1 is a flat HTTP GET against a link-local address. SSRF in the application can read the instance role's credentials. IMDSv2 requires a session token that has to be obtained with a PUT — application-side SSRF (which is almost always GET-only) can't get the token, so can't read credentials. Cost: zero. There's no reason not to enforce it.

## Why `health_check_type = "ELB"` on the ASG?

The default is EC2-level health checks — instance has to fully crash before the ASG replaces it. With ELB checks, the ASG also listens to the target group: if the app stops responding to `/health` past the unhealthy threshold, the ASG terminates and replaces the instance even though the OS is still up. Catches stuck processes, deadlocks, OOM-but-not-yet-killed, etc.

## Why is the health check `/health` and not `/`?

`/` does real work (Secrets Manager + DB query). If the DB hiccups, `/` returns an error and the ALB pulls every instance out of rotation simultaneously — taking the whole site down for a transient DB issue that the app would have ridden out. `/health` returns 200 unconditionally; it tests "is the process alive and accepting HTTP" only.

## Why an S3 + DynamoDB backend instead of local state?

Local state means: only one person can apply, the file is on a laptop that gets reformatted, and there's no audit trail. S3 + DynamoDB gives you concurrent-apply protection (the lock), encrypted storage, and version history (for "I just `terraform destroy`d, undo"). The bootstrap stack is the chicken-and-egg solution — it uses local state itself, but it only ever creates two resources, so the blast radius of losing its state file is "run `terraform import`" not "lose production."

## Why tag everything?

Cost allocation. AWS Cost Explorer lets you slice the bill by tag. With `Project`, `Environment`, and `Owner` on every resource, you can answer "how much did this stack cost last month?" in one query — and "which team owns the $400/month thing in our account?" almost as fast.
