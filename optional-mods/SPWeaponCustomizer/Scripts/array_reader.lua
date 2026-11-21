-- Synchronous, bounded reads only; never use an unchecked TArray index.
return function(array,limit,label,visit)
    local function count()
        local n=array:GetArrayNum()
        assert(type(n)=='number' and n>=0 and n%1==0 and n<=limit,'Unexpected '..label..' count')
        return n
    end
    local n=count()
    for i=1,n do
        assert(count()==n,label..' changed before indexed read')
        local value=array[i]
        assert(value~=nil,'Missing '..label..' element '..i)
        visit(i,value)
        assert(count()==n,label..' changed during indexed read')
    end
end
