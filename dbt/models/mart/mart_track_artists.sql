{{ config(
    materialized='table',
    cluster_by=['artist_id']
) }}

with int_ta as (

    select * from {{ ref('int_track_artists') }}

),

fct as (

    select * from {{ ref('fct_saved_tracks') }}

),

dim_date as (

    select * from {{ ref('dim_date') }}

),

dim_artist as (

    select * from {{ ref('dim_artist') }}

),

final as (

    select
        -- 日時
        fct.added_at,
        fct.added_datetime,
        dim_date.year,
        dim_date.month,
        int_ta.track_id,

        -- トラック × アーティスト
        int_ta.artist_id,
        dim_artist.artist_name,
        dim_artist.spotify_url as artist_spotify_url,
        date(fct.added_datetime) as added_date

    from int_ta
    left join fct on int_ta.track_id = fct.track_id
    left join dim_date on fct.date_id = dim_date.date_id
    left join dim_artist on int_ta.artist_id = dim_artist.artist_id

)

select * from final
