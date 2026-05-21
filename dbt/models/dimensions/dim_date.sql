with date_spine as (

    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="cast('2005-01-01' as date)",
        end_date="date_add(current_date(), interval 1 day)"
    ) }}

),

final as (

    select
        cast(format_date('%Y%m%d', date_day) as int64) as date_id,
        date_day as calendar_date,
        extract(year from date_day) as year,
        extract(month from date_day) as month,
        extract(day from date_day) as day,
        extract(dayofweek from date_day) as day_of_week
    from date_spine

)

select * from final
