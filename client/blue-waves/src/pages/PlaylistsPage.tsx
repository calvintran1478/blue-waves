import { useContext, Signal, createResource, For, Show, Suspense, createSignal } from "solid-js";
import { A } from "@solidjs/router";
import { Store } from "solid-js/store";
import { getToken } from "../utils/token"; 
import { apiDomain, AuthContext, MusicPlayerStateContext } from "../index.tsx";
import AddPlaylistModal from "../components/AddPlaylistModal"; 
import UpdatePlaylistModal from "../components/UpdatePlaylistModal";

const PlaylistsPage = () => {
    document.title = "Blue waves";

    const [showAddPlaylistModal, setShowAddPlaylistModal] = createSignal(false);
    const [showUpdatePlaylistModal, setShowUpdatePlaylistModal] = createSignal(false);

    let selectedPlaylistId = "";

    const [token, setToken] = useContext(AuthContext) as Signal<string>;

    const [musicPlayerState] = useContext(MusicPlayerStateContext) as Store<any>;

    const fetchPlaylists = async () => {
        // Fetch new token if user refreshed the page
        if (token() === "") setToken(await getToken());

        // Get playlists
        const response = await fetch(`${apiDomain}/api/v1/users/playlists`, {
            headers: { "Authorization": `Bearer ${token()}` }
        });

        if (response.ok) {
            const buffer = await response.arrayBuffer();
            const view = new DataView(buffer);
            const decoder = new TextDecoder("utf-8");
            const playlists = [];
            let index = 0;

            while (index < buffer.byteLength) {
                // Decode playlist id
                const playlistIdBytes = new Uint8Array(buffer, index, 22);
                const playlistId = decoder.decode(playlistIdBytes);
                index += 22;

                // Decode playlist name
                const nameLength = view.getInt32(index);
                const nameBytes = new Uint8Array(buffer, index + 4, nameLength);
                const name = decoder.decode(nameBytes);
                index += 4 + nameLength;

                // Add playlist
                playlists.push({"playlist_id": playlistId, "name": name});
            }
            
            return playlists;
        } else if (response.status === 401) {
            setToken(await getToken());
            return await fetchPlaylists();
        } else {
            return [];
        }
    }

    const [playlists, modifyPlaylists] = createResource(fetchPlaylists);

    return (
        <div class="flex flex-row-reverse">
            <div class={`flex flex-col w-1/5 ${musicPlayerState.showMusicPlayer ? "h-[calc(100vh-5rem)]" : "h-screen"} border-r-2 fixed left-0`}>
                <nav class="flex flex-col items-center p-6">
                    <A href="/home" class="text-2xl font-medium m-6">Home</A>
                    <A href="/library" class="text-2xl font-medium m-6">Library</A>
                    <A href="/playlists" class="text-2xl font-medium m-6">Playlists</A>
                </nav>
            </div>
            <div class="flex flex-col w-4/5 mb-20">
                <h1 class="text-3xl font-semibold mt-16 mb-4">Your Playlists</h1>
                <button class="rounded w-28 h-10 border-2 my-2" onClick={() => setShowAddPlaylistModal(true)}>Add Playlist</button>
                <hr class="border my-2"/>
                <Suspense>
                    <For each={playlists()}>
                        {(playlist) => (
                            <div class="flex justify-between items-center h-16 w-auto my-2 border-2">
                                    <A href={playlist["playlist_id"]}>
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

export default PlaylistsPage;
