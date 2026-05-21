{{ config(
    materialized='table',
    partition_by={
        'field': 'added_at',
        'data_type': 'timestamp',
        'granularity': 'day'
    },
    cluster_by=['track_id']
) }}

with fct as (

    select * from {{ ref('fct_saved_tracks') }}

),

dim_track as (

    select * from {{ ref('dim_track') }}

),

dim_date as (

    select * from {{ ref('dim_date') }}

),

final as (

    select
        -- 日時
        fct.added_at,
        fct.added_datetime,
        date(fct.added_datetime)                              as added_date,
        dim_date.year,
        dim_date.month,
        dim_date.day,
        dim_date.day_of_week,

        -- トラック
        fct.track_id,
        dim_track.track_name,
        dim_track.duration_ms,
        round(dim_track.duration_ms / 60000.0, 2)            as duration_min,
        dim_track.explicit,
        dim_track.isrc,
        dim_track.spotify_url,

        -- アルバム
        dim_track.album_id,
        dim_track.album_name,
        dim_track.album_type,
        dim_track.album_release_date,
        safe_cast(left(dim_track.album_release_date, 4) as int64) as album_release_year

    from fct
    left join dim_track using (track_id)
    left join dim_date using (date_id)

)

select * from final
