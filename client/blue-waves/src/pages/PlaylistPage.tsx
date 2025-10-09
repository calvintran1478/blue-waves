import { createResource, useContext, createSignal, For, Signal, Suspense } from "solid-js";
import { A } from "@solidjs/router";
import { useParams } from "@solidjs/router";
import { getToken } from "../utils/token"; 
import { AuthContext } from "..";

const PlaylistPage = () => {
    const params = useParams();
    const playlistId = params.playlist_id;

    const [token, setToken] = useContext(AuthContext) as Signal<string>;

    const [playlistName, setPlaylistName] = createSignal("");

    const fetchPlaylist = async () => {
        // Fetch new token if user refreshed the page
        if (token() === "") setToken(await getToken());

        // Get playlist music
        const response = await fetch(`http://localhost:8080/api/v1/users/playlists/${playlistId}`, {
            headers: { "Authorization": `Bearer ${token()}` }
        });

        if (response.ok) {
            const body = await response.json();
            setPlaylistName(body["name"]);
            return body["music"];
        } else if (response.status === 401) {
            setToken(await getToken());
            return await fetchPlaylist();
        }
    }

    const [playlistMusic] = createResource(fetchPlaylist);

    return (
        <div class="flex">
            <div class="flex flex-col w-1/5 h-screen border-2">
                <nav class="flex flex-col items-center p-6">
                    <A href="/home" class="text-2xl font-medium m-6">Home</A>
                    <A href="/library" class="text-2xl font-medium m-6">Library</A>
                    <A href="/playlists" class="text-2xl font-medium m-6">Playlists</A>
                </nav>
            </div>
            <div class="flex flex-col w-4/5">
                <Suspense>
                    <h1 class="text-3xl font-semibold mt-16 mb-4">{playlistName()}</h1>
                    <hr class="border my-2"/>
                    <For each={playlistMusic()}>
                        {(musicEntry) => (
                            <div class="flex justify-between items-center h-16 w-auto my-2 border-2">
                                <A href={musicEntry["music_id"]}>
                                    <div>
                                        <h2 class="text-lg font-semibold">{musicEntry["title"]}</h2>
                                        <h3 class="text-lg">{musicEntry["artist"]}</h3>
                                    </div>
                                </A>
                            </div>
                        )}
                    </For>
                </Suspense>
            </div>
        </div>
    )
}

export default PlaylistPage;
