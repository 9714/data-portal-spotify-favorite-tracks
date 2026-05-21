{{ config(cluster_by=['track_id']) }}

with stg as (

    select * from {{ ref('stg_saved_tracks') }}

),

deduped as (

    select
        track_id,
        track_name,
        duration_ms,
        explicit,
        isrc,
        spotify_url,
        album_id,
        album_name,
        album_type,
        album_release_date
    from stg
    where track_id is not null
    qualify row_number() over (partition by track_id order by added_at desc) = 1

)

select * from deduped
