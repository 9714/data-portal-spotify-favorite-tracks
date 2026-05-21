with stg as (

    select
        track_id,
        artists
    from {{ ref('stg_saved_tracks') }}

),

final as (

    select
        track_id,
        json_value(artist, '$.id') as artist_id,
        json_value(artist, '$.name') as artist_name,
        json_value(artist, '$.external_urls.spotify') as spotify_url
    from stg,
        unnest(json_query_array(artists)) as artist
    where
        track_id is not null
        and json_value(artist, '$.id') is not null

)

select * from final
