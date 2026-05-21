{{ config(cluster_by=['artist_id']) }}

with int_track_artists as (

    select * from {{ ref('int_track_artists') }}

),

stg_artists as (

    select * from {{ ref('stg_artists') }}

),

deduped as (

    select
        ita.artist_id,
        ita.artist_name,
        ita.spotify_url,
        sa.genres,
        sa.popularity
    from int_track_artists as ita
    left join stg_artists as sa on ita.artist_id = sa.artist_id
    where ita.artist_id is not null
    qualify
        row_number() over (partition by ita.artist_id order by ita.artist_id)
        = 1

)

select * from deduped
