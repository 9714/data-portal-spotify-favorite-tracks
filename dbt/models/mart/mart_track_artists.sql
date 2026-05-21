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
        date(fct.added_datetime) as added_date,
        dim_date.year,
        dim_date.month,

        -- トラック × アーティスト
        int_ta.track_id,
        int_ta.artist_id,
        dim_artist.artist_name,
        dim_artist.spotify_url as artist_spotify_url

    from int_ta
    left join fct         using (track_id)
    left join dim_date    using (date_id)
    left join dim_artist  using (artist_id)

)

select * from final
