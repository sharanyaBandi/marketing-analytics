-- SIM-004: The Customers We Paid For
-- PostgreSQL-style analytical SQL.

-- 01_Data_Cleaning
CREATE TEMP TABLE clean_orders AS SELECT DISTINCT * FROM orders;
CREATE TEMP TABLE clean_customers AS SELECT *, CASE
WHEN LOWER(REPLACE(TRIM(acquisition_channel),'_',' ')) IN ('affiliate','referral') THEN 'Affiliate Referral Network'
WHEN LOWER(REPLACE(TRIM(acquisition_channel),'_',' '))='influencer' THEN 'Social Media Influencer'
WHEN LOWER(REPLACE(TRIM(acquisition_channel),'_',' '))='direct' THEN 'Direct'
WHEN LOWER(REPLACE(TRIM(acquisition_channel),'_',' '))='facebook ads' THEN 'Facebook Ads'
WHEN LOWER(REPLACE(TRIM(acquisition_channel),'_',' '))='google ads' THEN 'Google Ads'
WHEN LOWER(REPLACE(TRIM(acquisition_channel),'_',' '))='instagram' THEN 'Instagram'
WHEN LOWER(REPLACE(TRIM(acquisition_channel),'_',' '))='organic' THEN 'Organic'
WHEN LOWER(REPLACE(TRIM(acquisition_channel),'_',' '))='organic search' THEN 'Organic Search'
WHEN LOWER(REPLACE(TRIM(acquisition_channel),'_',' '))='paid search' THEN 'Paid Search'
WHEN LOWER(REPLACE(TRIM(acquisition_channel),'_',' '))='paid social' THEN 'Paid Social'
WHEN LOWER(REPLACE(TRIM(acquisition_channel),'_',' '))='youtube' THEN 'YouTube'
WHEN LOWER(REPLACE(TRIM(acquisition_channel),'_',' '))='youtube promo' THEN 'Youtube Promo' ELSE TRIM(acquisition_channel) END AS channel_standardized FROM customers;

-- 02_Baseline_Financials
WITH f AS (SELECT o.order_id,EXTRACT(YEAR FROM CAST(o.order_date AS DATE)) yr,o.gross_amount,o.discount_amount,o.net_revenue,o.quantity*p.unit_cost cogs,COALESCE(SUM(r.refund_amount),0) refund_amount FROM clean_orders o JOIN products p USING(product_id) LEFT JOIN returns r USING(order_id) GROUP BY o.order_id,o.order_date,o.gross_amount,o.discount_amount,o.net_revenue,o.quantity,p.unit_cost) SELECT yr,SUM(gross_amount) gross_revenue,SUM(discount_amount) discounts,SUM(refund_amount) refunds,SUM(net_revenue-refund_amount) realized_revenue,SUM(cogs) cogs,SUM(net_revenue-refund_amount-cogs) realized_profit,ROUND(100.0*SUM(net_revenue-refund_amount-cogs)/NULLIF(SUM(net_revenue-refund_amount),0),2) realized_profit_margin FROM f GROUP BY yr ORDER BY yr;

-- 03_Channel_Economics
WITH co AS (SELECT c.customer_id,c.channel_standardized,COUNT(DISTINCT o.order_id) order_count FROM clean_customers c LEFT JOIN clean_orders o USING(customer_id) GROUP BY c.customer_id,c.channel_standardized), cp AS (SELECT c.customer_id,c.channel_standardized,COALESCE(SUM(o.net_revenue),0)-COALESCE(SUM(r.refund_amount),0)-COALESCE(SUM(o.quantity*p.unit_cost),0) realized_profit FROM clean_customers c LEFT JOIN clean_orders o USING(customer_id) LEFT JOIN products p USING(product_id) LEFT JOIN returns r USING(order_id) GROUP BY c.customer_id,c.channel_standardized), ce AS (SELECT mc.channel,SUM(mc.campaign_spend) spend,SUM(cp.attributed_customers) attributed FROM marketing_campaigns mc JOIN campaign_performance cp USING(campaign_id) GROUP BY mc.channel) SELECT co.channel_standardized,COUNT(*) signups,COUNT(*) FILTER(WHERE order_count=1) one_time_buyers,ROUND(100.0*COUNT(*) FILTER(WHERE order_count=1)/COUNT(*),2) one_time_rate,ce.spend,ce.attributed,ROUND(ce.spend/NULLIF(ce.attributed,0),2) CAC,SUM(cp.realized_profit) realized_profit,ROUND(SUM(cp.realized_profit)/COUNT(*),2) CLV FROM co JOIN cp USING(customer_id,channel_standardized) JOIN ce ON ce.channel=co.channel_standardized WHERE co.channel_standardized IN('Affiliate Referral Network','Paid Search','Paid Social','Social Media Influencer') GROUP BY co.channel_standardized,ce.spend,ce.attributed;

-- 04_Category_Retention
WITH fo AS (SELECT o.*,ROW_NUMBER() OVER(PARTITION BY customer_id ORDER BY CAST(order_date AS DATE),order_id) rn FROM clean_orders o), fc AS (SELECT fo.customer_id,p.category FROM fo JOIN products p USING(product_id) WHERE rn=1), oc AS (SELECT customer_id,COUNT(DISTINCT order_id) order_count FROM clean_orders GROUP BY customer_id) SELECT fc.category first_purchase_category,COUNT(*) customers,COUNT(*) FILTER(WHERE oc.order_count>1) repeat_customers,ROUND(100.0*COUNT(*) FILTER(WHERE oc.order_count>1)/COUNT(*),2) repeat_rate FROM fc JOIN oc USING(customer_id) GROUP BY fc.category ORDER BY repeat_rate DESC;

-- 05_Support_CSAT_Impact
WITH fi AS (SELECT *,ROW_NUMBER() OVER(PARTITION BY customer_id ORDER BY CAST(interaction_date AS DATE),interaction_id) rn FROM customer_interactions), oc AS (SELECT customer_id,COUNT(DISTINCT order_id) order_count FROM clean_orders GROUP BY customer_id) SELECT CASE WHEN satisfaction_score>=4 THEN 'High CSAT (4-5)' WHEN satisfaction_score<=2 THEN 'Low CSAT (1-2)' ELSE 'Medium CSAT (3)' END csat_group,COUNT(*) customers,COUNT(*) FILTER(WHERE oc.order_count>1) repeat_customers,ROUND(100.0*COUNT(*) FILTER(WHERE oc.order_count>1)/COUNT(*),2) repeat_rate FROM fi JOIN oc USING(customer_id) WHERE rn=1 GROUP BY 1;

-- Delivery issue in first 30 days
WITH fo AS (SELECT customer_id,MIN(CAST(order_date AS DATE)) first_order_date FROM clean_orders GROUP BY customer_id), df AS (SELECT fo.customer_id,EXISTS(SELECT 1 FROM customer_interactions ci WHERE ci.customer_id=fo.customer_id AND ci.issue_category='Delivery Issue' AND CAST(ci.interaction_date AS DATE) BETWEEN fo.first_order_date AND fo.first_order_date+INTERVAL '30 day') delivery_issue FROM fo), oc AS (SELECT customer_id,COUNT(DISTINCT order_id) order_count FROM clean_orders GROUP BY customer_id) SELECT delivery_issue,COUNT(*) customers,COUNT(*) FILTER(WHERE oc.order_count>1) repeat_customers,ROUND(100.0*COUNT(*) FILTER(WHERE oc.order_count>1)/COUNT(*),2) repeat_rate FROM df JOIN oc USING(customer_id) GROUP BY delivery_issue;

-- 06_Influencer_Returns
WITH f AS (SELECT o.order_id,c.channel_standardized,o.gross_amount,o.net_revenue,o.quantity*p.unit_cost cogs,COALESCE(SUM(r.refund_amount),0) refund_amount FROM clean_orders o JOIN clean_customers c USING(customer_id) JOIN products p USING(product_id) LEFT JOIN returns r USING(order_id) WHERE c.channel_standardized IN('Social Media Influencer','Paid Social') GROUP BY o.order_id,c.channel_standardized,o.gross_amount,o.net_revenue,o.quantity,p.unit_cost) SELECT channel_standardized,SUM(gross_amount) gross_revenue,SUM(refund_amount) refunds,ROUND(100.0*SUM(refund_amount)/NULLIF(SUM(gross_amount),0),2) return_rate,SUM(net_revenue-refund_amount) realized_revenue,SUM(cogs) cogs,SUM(net_revenue-refund_amount-cogs) realized_profit,ROUND(100.0*SUM(net_revenue-refund_amount-cogs)/NULLIF(SUM(net_revenue-refund_amount),0),2) realized_profit_margin FROM f GROUP BY channel_standardized;
