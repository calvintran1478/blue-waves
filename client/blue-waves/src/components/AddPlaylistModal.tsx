import { useContext, Resource, Signal, Setter } from "solid-js";
import { apiDomain, AuthContext } from "../index.tsx";
import { getToken } from "../utils/token"; 

// Expected fields for each playlist
interface Playlist {
    playlist_id: string,
    name: string
}

const AddPlaylistModal = (props: { closeCallback: () => void, playlists: Resource<Playlist[]>, setPlaylists: Setter<Playlist[] | undefined> }) => {

    let name = "";

    const [token, setToken] = useContext(AuthContext) as Signal<string>;

    const addPlaylist = async (event: Event) => {
        // Prevent refresh
        event.preventDefault();

        const response = await fetch(`${apiDomain}/api/v1/users/playlists`, {
            method: "POST",
            headers: { "Authorization": `Bearer ${token()}` },
            body: name
        });

        if (response.ok) {
            // Add playlist entry to list
            const newPlaylists = [...props.playlists()!];
            const response_body = await response.text();
            const newline_index = response_body.indexOf('\n');
            const playlist = {
                playlist_id: response_body.substring(0, newline_index),
                name: response_body.substring(newline_index + 1)
            }
            newPlaylists!.push(playlist);
            props.setPlaylists(newPlaylists);

            // Close modal
            props.closeCallback();
        } else if (response.status === 401) {
            setToken(await getToken());
            await addPlaylist(event);
        }
    }

    return (
        <div class="p-6 bg-white" style="width: 36rem; height: 16rem;">
            <div class="flex flex-row-reverse">
                <button onClick={props.closeCallback}>close</button>
            </div>
            <form onSubmit={addPlaylist} class="flex flex-col items-center">
                <div class="flex items-center m-5">
                    <label for="name" class="text-lg m-2">Name</label>
                    <input id="name" class="border-2 m-2 w-60 h-8" onChange={(event) => {name = event.target.value}} maxlength={80} required/>
                </div>
                <button class="inline-flex items-center border-2 rounded m-4 p-3 bg-neutral-400">Add Playlist</button>
            </form>
        </div>
    )
}

export default AddPlaylistModal;
