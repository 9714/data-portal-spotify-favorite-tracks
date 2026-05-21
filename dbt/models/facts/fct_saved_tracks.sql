{{ config(
    partition_by={
        'field': 'added_at',
        'data_type': 'timestamp',
        'granularity': 'day'
    },
    cluster_by=['track_id']
) }}

with stg as (

    select * from {{ ref('stg_saved_tracks') }}

),

dim_date as (

    select * from {{ ref('dim_date') }}

),

final as (

    select
        stg.added_at,
        stg.added_datetime,
        stg.track_id,
        dim_date.date_id
    from stg
    left join dim_date
        on stg.added_date = dim_date.calendar_date

)

select * from final
