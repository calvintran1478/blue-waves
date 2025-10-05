import { useContext, Signal, createResource, For, Show, Suspense, createSignal } from "solid-js";
import { A } from "@solidjs/router";
import { getToken } from "../utils/token"; 
import { AuthContext } from "..";
import AddPlaylistModal from "../components/AddPlaylistModal"; 
import UpdatePlaylistModal from "../components/UpdatePlaylistModal";

const PlaylistPage = () => {

    const [showAddPlaylistModal, setShowAddPlaylistModal] = createSignal(false);
    const [showUpdatePlaylistModal, setShowUpdatePlaylistModal] = createSignal(false);

    let selectedPlaylistId = "";

    const [token, setToken] = useContext(AuthContext) as Signal<string>;

    const fetchPlaylists = async () => {
        // Fetch new token if user refreshed the page
        if (token() === "") setToken(await getToken());

        // Get playlists
        const response = await fetch("http://localhost:8080/api/v1/users/playlists", {
            headers: { "Authorization": `Bearer ${token()}` }
        });

        if (response.ok) {
            return await response.json();
        } else if (response.status === 401) {
            setToken(await getToken());
            return await fetchPlaylists();
        }
    }

    const [playlists, modifyPlaylists] = createResource(fetchPlaylists);

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
                <h1 class="text-3xl font-semibold mt-16 mb-4">Your Playlists</h1>
                <button class="rounded w-28 h-10 border-2 my-2" onClick={() => setShowAddPlaylistModal(true)}>Add Playlist</button>
                <hr class="border my-2"/>
                <Suspense>
                    <For each={playlists()}>
                        {(playlist) => (
                            <div class="flex justify-between items-center h-16 w-auto my-2 border-2">
                                    <A href="">
                                        <div>
                                            <h2 class="text-xl font-semibold">{playlist["name"]}</h2>
                                        </div>
                                    </A>
                                    <button class="rounded w-10 h-7 border-2 m-4" onMouseOver={() => {selectedPlaylistId = playlist["playlist_id"]}} onClick={() => setShowUpdatePlaylistModal(true)}>...</button>
                            </div>
                        )}
                    </For>
                </Suspense>
            </div>
            <Show when={showAddPlaylistModal()}>
                <div class="flex justify-center items-center h-screen w-screen fixed inset-0 bg-black/50">
                    <AddPlaylistModal closeCallback={() => setShowAddPlaylistModal(false)} playlists={playlists} setPlaylists={modifyPlaylists.mutate}/>
                </div>
            </Show>
            <Show when={showUpdatePlaylistModal()}>
                <div class="flex justify-center items-center h-screen w-screen fixed inset-0 bg-black/50">
                    <UpdatePlaylistModal playlistId={selectedPlaylistId} closeCallback={() => setShowUpdatePlaylistModal(false)} playlists={playlists} setPlaylists={modifyPlaylists.mutate}/>
                </div>
            </Show>
        </div>
    )
}

export default PlaylistPage;
