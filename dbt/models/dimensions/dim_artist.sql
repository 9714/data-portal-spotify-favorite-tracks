{{ config(cluster_by=['artist_id']) }}

with int_track_artists as (

    select * from {{ ref('int_track_artists') }}

),

deduped as (

    select
        artist_id,
        artist_name,
        spotify_url
    from int_track_artists
    where artist_id is not null
    qualify row_number() over (partition by artist_id order by artist_id) = 1

)

select * from deduped
