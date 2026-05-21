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

track_artists as (

    select
        track_id,
        string_agg(artist_name, ' / ' order by artist_name) as artist_names
    from {{ ref('int_track_artists') }}
    group by track_id

),

final as (

    select
        -- 日時
        fct.added_at,
        fct.added_datetime,
        dim_date.year,
        dim_date.month,
        dim_date.day,
        dim_date.day_of_week,
        fct.track_id,

        -- トラック
        dim_track.track_name,
        track_artists.artist_names,
        dim_track.duration_ms,
        dim_track.explicit,
        dim_track.isrc,
        dim_track.spotify_url,
        dim_track.album_id,
        dim_track.album_name,

        -- アルバム
        dim_track.album_type,
        dim_track.album_release_date,
        date(fct.added_datetime) as added_date,
        round(dim_track.duration_ms / 60000.0, 2) as duration_min,
        safe_cast(left(dim_track.album_release_date, 4) as int64)
            as album_release_year

    from fct
    left join dim_track on fct.track_id = dim_track.track_id
    left join dim_date on fct.date_id = dim_date.date_id
    left join track_artists on fct.track_id = track_artists.track_id

)

select * from final
