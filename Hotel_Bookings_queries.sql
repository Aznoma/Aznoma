CREATE TABLE IF NOT EXISTS hotel_project.hotel_bookings 
(
hotel VARCHAR(30), is_canceled BOOLEAN, lead_time SMALLINT, arrival_year VARCHAR(4), arrival_month VARCHAR(10), arrival_day VARCHAR (2), weekend_nights SMALLINT, week_nights SMALLINT, 
adults SMALLINT, children SMALLINT, babies SMALLINT, meal VARCHAR(5), country VARCHAR(5), market_segment VARCHAR(30), is_repeated_guest BOOLEAN, previous_cancellations SMALLINT,
previous_bookings_not_canceled SMALLINT, reserved_room_type CHAR(1), assigned_room_type CHAR(1), booking_changes VARCHAR(2), deposit_type VARCHAR(20), agent VARCHAR(5),
company VARCHAR(5), days_in_waiting_list SMALLINT, customer_type VARCHAR(20), adr NUMERIC(1), required_car_parking_spaces SMALLINT, total_special_requests SMALLINT, 
reservation_status VARCHAR(20), reservation_status_date DATE
);

--Added id column to the table
ALTER TABLE hotel_project.hotel_bookings
ADD COLUMN id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY;

--Found 'NA' values in market_segment and changed to NULL
UPDATE hotel_project.hotel_bookings
SET market_segment=NULL WHERE market_segment='NA';

--2 rows with NULL market_segment and is_canceled = TRUE, were deleted from the table:
DELETE FROM hotel_project.hotel_bookings
WHERE market_segment IS NULL;


--Next, I created a function that allows to use the full arrival_date:
DROP FUNCTION IF EXISTS arrivalDate;
CREATE FUNCTION arrivalDate (rec hotel_project.hotel_bookings)
RETURNS date
LANGUAGE SQL
AS $$ SELECT CAST(CONCAT($1.arrival_year || '-' || $1.arrival_month || '-' || $1.arrival_day) AS DATE)
$$;

--Finding the cancellation percentages by hotel and lead time (binned into categories):
SELECT hotel,
	CASE WHEN lead_time < 8 THEN 'Week or less'
	WHEN lead_time < 29 THEN '1 to 4 weeks'
	WHEN lead_time < 91 THEN '4 weeks to 90 days'
	ELSE 'More than 90 days' END AS lead_time_cat,
	(COUNT(*) FILTER(WHERE is_canceled = TRUE))/COUNT(*)::DECIMAL*100 AS lead_time_cancel_perc
FROM hotel_project.hotel_bookings
GROUP BY hotel, lead_time_cat
ORDER BY hotel;

--Average number of guests by age group, hotel, and month
SELECT month_no, hotel, average_adults, average_children, average_babies, COALESCE(average_adults,0)+COALESCE(average_children,0)+COALESCE(average_babies,0) AS total_average
FROM (
	SELECT to_char(to_date(arrival_month, 'Month'), 'MM') AS month_no, hotel, AVG(adults) AS average_adults, AVG(children) AS average_children, AVG(babies) AS average_babies
	FROM hotel_project.hotel_bookings
	GROUP BY arrival_month, hotel);

--Cancellation rates by market segment (found NULL market segment values)
SELECT market_segment, (COUNT(*) FILTER(WHERE is_canceled = TRUE))/COUNT(*)::DECIMAL*100 AS segment_cancel_perc
FROM hotel_project.hotel_bookings
WHERE market_segment IS NOT NULL
GROUP BY ROLLUP(market_segment)
ORDER BY segment_cancel_perc DESC;

--Repeated guest shares by hotel and market segment
SELECT hotel, market_segment, (COUNT(*) FILTER(WHERE is_repeated_guest = TRUE))/COUNT(*)::DECIMAL*100 AS repeated_guest_perc
FROM hotel_project.hotel_bookings
GROUP BY ROLLUP(hotel, market_segment)
ORDER BY repeated_guest_perc DESC;

--Count of bookings by country
SELECT country, COUNT(*) AS bookings_count
FROM hotel_project.hotel_bookings
GROUP BY country
ORDER BY bookings_count DESC;

--Room type change prevalence by year and month
SELECT arrival_year, EXTRACT(MONTH FROM hotel_bookings.arrivalDate) AS month_no, (COUNT(*) FILTER(WHERE reserved_room_type != assigned_room_type))/COUNT(*)::DECIMAL*100 AS changed_room_perc
FROM hotel_project.hotel_bookings
GROUP BY arrival_year, month_no
ORDER BY arrival_year, month_no;

--Share of bookings with changes made and the average, maximum number of booking changes by market segment and month
SELECT market_segment, EXTRACT(MONTH FROM hotel_bookings.arrivalDate) AS month_no, COUNT(*) AS total_bookings, (COUNT(*) FILTER(WHERE booking_changes::INT > 0))/COUNT(*)::DECIMAL * 100 AS changed_bookings_perc, AVG(booking_changes::INT) AS average_booking_changes, MAX(booking_changes::INT) AS max_booking_changes
FROM hotel_project.hotel_bookings
GROUP BY ROLLUP(market_segment, month_no)
ORDER BY market_segment, month_no;

--Average nights by market segments compared to total average
SELECT market_segment, AVG(weekend_nights + week_nights) AS avg_nights
FROM hotel_project.hotel_bookings
WHERE market_segment IS NOT NULL
GROUP BY ROLLUP(market_segment)
ORDER BY avg_nights DESC;

--Repeated guests' adr compared by hotel and customer type
SELECT hotel, customer_type, is_repeated_guest, AVG(adr) AS avg_daily_rate
FROM hotel_project.hotel_bookings
GROUP BY hotel, customer_type, is_repeated_guest
ORDER BY avg_daily_rate DESC;

--Stats of previous non-canceled bookings by hotel and market segment
SELECT hotel, market_segment, AVG(previous_bookings_not_canceled) AS avg_prev_checkouts, MAX(previous_bookings_not_canceled) AS max_prev_checkouts
FROM hotel_project.hotel_bookings
WHERE is_canceled = FALSE
GROUP BY hotel, market_segment
ORDER BY avg_prev_checkouts DESC;

--Previous cancellations by hotel and special requests' presence   ***(need to review whether to keep!)
SELECT hotel, 
 CASE WHEN total_special_requests > 0 THEN 'With special requests'
 WHEN total_special_requests = 0 THEN 'No special requests'
 ELSE 'Not specified' END AS spec_req_status,
AVG(previous_cancellations) AS prev_cancellations
FROM hotel_project.hotel_bookings
WHERE is_canceled = FALSE
GROUP BY hotel, spec_req_status;

--adr and revenue stats by hotel and deposit type
SELECT DISTINCT hotel, deposit_type,
AVG(adr) OVER (PARTITION BY hotel, deposit_type) AS avg_adr,
MAX(adr) OVER (PARTITION BY hotel, deposit_type) AS max_adr,
SUM(week_nights + weekend_nights) OVER (PARTITION BY hotel, deposit_type) AS total_nights,
SUM(adr*(week_nights + weekend_nights)) OVER (PARTITION BY hotel, deposit_type)::DECIMAL(10,2) AS total_revenue
FROM hotel_project.hotel_bookings
WHERE is_canceled = FALSE;

-- Checkout count and total revenue by agent
SELECT agent, COUNT(*) AS checkout_count, SUM(adr*(weekend_nights + week_nights))::DECIMAL(10,2) AS total_revenue
FROM hotel_project.hotel_bookings
WHERE reservation_status = 'Check-Out' 
	AND agent IS NOT NULL
GROUP BY agent
HAVING COUNT(*) > 49
ORDER BY checkout_count DESC;

-- Checkout count and total revenue by company
SELECT company, COUNT(*) AS checkout_count, SUM(adr*(weekend_nights + week_nights))::DECIMAL(10,2) AS total_revenue
FROM hotel_project.hotel_bookings
WHERE reservation_status = 'Check-Out' 
	AND company IS NOT NULL
GROUP BY company
HAVING COUNT(*) > 49
ORDER BY checkout_count DESC;

-- Maximum days in waiting list by hotel and customer_type
SELECT hotel, customer_type, AVG(adr) AS avg_adr, MAX(days_in_waiting_list) max_waiting_list_days, COUNT(*) AS total_count
FROM hotel_project.hotel_bookings
WHERE reservation_status = 'Check-Out'
GROUP BY hotel, customer_type;

-- Avg adr and max car parking spaces by hotel, stay length category, and lead time category
SELECT hotel,
	CASE WHEN week_nights + weekend_nights < 3 THEN '1-2 nights'
	WHEN week_nights + weekend_nights < 8 THEN '3-7 nights'
	ELSE '7+ nights' END AS stay_length_cat,
	CASE WHEN lead_time < 8 THEN 'Week or less'
	WHEN lead_time < 29 THEN '1 to 4 weeks'
	WHEN lead_time < 91 THEN '4 weeks to 90 days'
	ELSE 'More than 90 days' END AS lead_time_cat,
	ROUND(AVG(adr)::DECIMAL, 2) AS avg_adr,
	MAX(required_car_parking_spaces) AS max_parking_spaces
FROM hotel_project.hotel_bookings
WHERE reservation_status = 'Check-Out'
GROUP BY hotel, stay_length_cat, lead_time_cat
ORDER BY max_parking_spaces DESC;

-- Median of total special requests and total count by price category
SELECT	price_cat,
		PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY total_special_requests) AS median_spec_requests,
		COUNT(*) AS total_checkouts
FROM (
SELECT CASE WHEN adr < 30 THEN 'Less than 30$ per night'
		WHEN adr < 100 THEN '30-99$ per night'
		WHEN adr < 300 THEN '100-299$ per night'
		ELSE '300$ or more per night' END AS price_cat,
		total_special_requests
FROM hotel_project.hotel_bookings
WHERE reservation_status = 'Check-Out')
GROUP BY price_cat
ORDER BY total_checkouts DESC;
