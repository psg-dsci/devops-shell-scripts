This creates an **Application Load Balancer** + **Auto Scaling Group** (min=1, max=3), installs Nginx on instances, **auto-starts CPU stress** to trigger scaling, and then **hits the ALB** for a few minutes to show load balancing and scale-out/-in in action. It also includes a **one-command destroy** mode to clean everything up.

- Copy / download and save as `asg-alb-demo.sh`, then run:
- `bash asg-alb-demo.sh`
> To clean up later: `bash asg-alb-demo.sh destroy`

### What this does (zero typing from you after running):

* Creates:
  * **ALB** (HTTP :80) + SG
  * **Target Group** (HTTP health checks)
  * **Launch Template** (Amazon Linux 2023, `t2.micro`, Nginx, page shows instance-id/AZ)
  * **Auto Scaling Group** (min=1, max=3) with **Target Tracking** on **ASG Average CPU = 40%**
  * **Auto stress** on each instance \~30 seconds after boot for **4 minutes**, to force **scale-out**
* The script then **curls the ALB for 5 minutes**, printing which **instance-id** served each request so students can see the **load balancer** distributing traffic and new instances joining as CPU spikes.
* After the stress ends and cooldown passes, ASG will scale back down automatically.
* **Destroy** everything later with: `bash asg-alb-demo.sh destroy`

> Pro tip: open a browser tab to the **ALB DNS** the script prints, so you can watch it live while the terminal logs which instance handled each request.
