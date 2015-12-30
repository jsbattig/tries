# tries

This class provides the basis to construct a Trie based container.

On it's basic form it can be used to store 16, 32 and 64 bits based data elements.

The structure provides a fixed depth Trie implementation, which in turns renders
equal time to Find and Remove nodes, and consistent Add times incurring only in
extra overhead when needing the acquire new nodes.

The order of the structure is O(D) where D is the depth of the Trie, which depends
if constructed to store 16, 32 or 64 bits values.
For 16 bits D = 4
For 32 bits D = 8
and For 64 bits D = 16

To keep node size small, only 16 branches per node will be used and indicator flags
and internal pointer indexes are encoded in a 16 bits word and in a 64 bits integer.

Pointers to branches are managed dynamically so only a pointer is allocated on the
pointers array when a new branch needs to be added, this minimizes waste of
pre-allocated pointers array to lower level branches. It will slowdown Adds though.

Leafs are allocated in-place rather than as individual nodes pointed by the last
branch node.

Finally, Leaf nodes can be dynamically controlled by the derived class from TTrie
allowing for easy implementation of dictionaries using TTrie as a base.

All in all, doing some tests storing memory allocated by Lazarus (FreePascal) 
allocator in a Mac renders around 40% storage efficiency in proportion to the size
of the objects stored, which is not bad given the performance for Add, Find and Remove
operations.

The class also provides a Pack method that be used to keep storage in check when lots
of Removed have been issued.
