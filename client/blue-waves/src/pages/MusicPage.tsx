import { createResource, useContext, Signal, Suspense } from "solid-js";
import { useParams } from "@solidjs/router";
import { until } from "@solid-primitives/promise"; 
import { openDB } from "idb";
import { getToken } from "../utils/token";
import { AuthContext } from "../index.tsx";

const MusicPage = () => {

    const params = useParams();

    const [token, setToken] = useContext(AuthContext) as Signal<string>;

    const fetchCoverArtFile = async () => {
        // Open music database
        const db = await openDB("musicFileDB", 1, {
            upgrade(database) {
                database.createObjectStore("musicFiles", { keyPath: "music_id" });
                database.createObjectStore("coverArtFiles", { keyPath: "music_id" });
            },
        })

        // Fetch new token if user refreshed the page
        if (token() === "") setToken(await getToken());

        // Check music database for a cached value
        const coverArtFileEntry = await db.get("coverArtFiles", params.music_id);
        if (coverArtFileEntry !== undefined) {
            // If a cached value exists perform a conditional request
            const response = await fetch(`http://localhost:8080/api/v1/users/music/${params.music_id}/cover-art`, {
                headers: {
                    "Authorization": `Bearer ${token()}`,
                    "If-Modified-Since": coverArtFileEntry["last_modified"]
                }
            });

            if (response.ok) {
                // Cache miss: decode new data and update cache
                const imageBuffer = await response.arrayBuffer();
                const blob = new Blob([imageBuffer])
                const url = window.URL.createObjectURL(blob);

                await db.put("coverArtFiles", {music_id: params.music_id, image_buffer: imageBuffer, last_modified: response.headers.get("Last-Modified")});

                return url;
            } else if (response.status === 304) {
                const blob = new Blob([coverArtFileEntry["image_buffer"]]);
                const url = window.URL.createObjectURL(blob);
                return url;
            } else if (response.status === 401) {
                setToken(await getToken());
                return await fetchCoverArtFile();
            }
        } else {
            // If no cached value exists perform a normal request for the music file
            const response = await fetch(`http://localhost:8080/api/v1/users/music/${params.music_id}/cover-art`, {
                headers: { "Authorization": `Bearer ${token()}` }
            });

            if (response.ok) {
                // Decode data as an image
                const imageBuffer = await response.arrayBuffer();
                const blob = new Blob([imageBuffer])
                const url = window.URL.createObjectURL(blob);

                // Cache cover art file for later requests
                await db.put("coverArtFiles", {music_id: params.music_id, image_buffer: imageBuffer, last_modified: response.headers.get("Last-Modified")});

                return url;
            } else if (response.status === 401) {
                setToken(await getToken());
                return await fetchCoverArtFile();
            }
        }
    }

    const [coverArtFile] = createResource(fetchCoverArtFile);

    const fetchMusicFile = async () => {
        // Open music database
        const db = await openDB("musicFileDB", 1, {
            upgrade(database) {
                database.createObjectStore("musicFiles", { keyPath: "music_id" });
                database.createObjectStore("coverArtFiles", { keyPath: "music_id" });
            },
        })

        // Check music database for a cached value
        const musicFileEntry = await db.get("musicFiles", params.music_id);
        if (musicFileEntry !== undefined) {
            // If cached value exists use it
            const blob = new Blob([musicFileEntry["music_buffer"]]);
            const url = window.URL.createObjectURL(blob);
            await until(() => coverArtFile() !== undefined);
            return url;
        } else {
            // Fetch new token if user refreshed the page
            if (token() === "") setToken(await getToken());

            // If no cached value exists perform a normal request for the music file
            const response = await fetch(`http://localhost:8080/api/v1/users/music/${params.music_id}`, {
                headers: { "Authorization": `Bearer ${token()}` }
            });

            if (response.ok) {
                // Decode data as a music file
                const musicBuffer = await response.arrayBuffer();
                const blob = new Blob([musicBuffer]);
                const url = window.URL.createObjectURL(blob);

                // Cache music file for later requests
                await db.put("musicFiles", {music_id: params.music_id, music_buffer: musicBuffer});

                await until(() => coverArtFile() !== undefined);
                return url;
            } else if (response.status === 401) {
                setToken(await getToken());
                return await fetchMusicFile();
            }
        }
    }

    const [musicFile] = createResource(fetchMusicFile);

    return (
        <div class="flex justify-center items-center w-screen h-screen">
            <div class="flex flex-col justify-center items-center aspect-video" style="width: 1080px">
                <Suspense>
                    <video controls poster={coverArtFile()} src={musicFile()}></video>
                </Suspense>
            </div>
        </div>
    )
}

export default MusicPage;
